"""Synthetic fixtures test the comparator, not Stata/R equivalence."""
import csv
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("compare", ROOT / "scripts/compare_outputs.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def write_csv(path, headers, rows):
    with path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        writer.writerows(rows)


def bundle(path, engine):
    path.mkdir()
    write_csv(path / "checkpoint.csv", ["id", "panel", "month", "x", "z", "y", "ma6", "sample"],
              [[i, (i - 1) // 2, i, 2, 3, 4, 2, 1] for i in range(1, 9)])
    terms = ["_cons", "x", "z", "ma6"]
    models = ["ols", "hc1", "cluster"]
    write_csv(path / "coefficients.csv", ["model", "term", "estimate", "se", "statistic", "p", "ci_low", "ci_high"],
              [[m, t, 1, .5, 2, .1, -.1, 2.1] for m in models for t in terms])
    write_csv(path / "vcov.csv", ["model", "term_i", "term_j", "value"],
              [[m, t, u, .25 if t == u else .01] for m in models for t in terms for u in terms])
    write_csv(path / "predictions.csv", ["id", "fitted", "residual"], [[i, 4, 0] for i in range(1, 9)])
    write_csv(path / "statistics.csv", ["model", "name", "value"],
              [[m, n, v] for m in models for n, v in [("N", 8), ("rank", 4), ("df_r", 3 if m == "cluster" else 4), ("N_clust", 4 if m == "cluster" else 0)]])
    runtime = [["R_version", "test-fixture"], ["sandwich_version", "test-fixture"]] if engine == "r" else [
        ["engine", "Stata"], ["stata_version", "17"], ["stata_edition", "BE"],
        ["stata_born_date", "test-fixture"], ["status", "completed"]]
    write_csv(path / "runtime.csv", ["key", "value"], runtime)
    seal(path, engine)


def seal(path, engine):
    manifest = {"schema_version": 1, "engine": engine, "status": "success", "input_sha256": "a" * 64,
                "source_sha256": {"synthetic-test": "b" * 64},
                "outputs_sha256": {n: mod.sha256(path / n) for n in mod.FILES}}
    (path / "manifest.json").write_text(json.dumps(manifest))


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ref = Path(self.tmp.name) / "reference"
        self.actual = Path(self.tmp.name) / "actual"
        bundle(self.ref, "stata")
        bundle(self.actual, "r")

    def compare(self, **kwargs):
        return mod.compare(self.ref, self.actual, **kwargs)

    def change(self, filename, old, new, seal_again=True):
        p = self.actual / filename
        p.write_text(p.read_text().replace(old, new, 1))
        if seal_again:
            seal(self.actual, "r")

    def test_match(self):
        self.assertEqual(self.compare()["status"], "MATCHED_OUTPUTS")

    def test_reordered_rows(self):
        p = self.actual / "checkpoint.csv"
        lines = p.read_text().splitlines()
        p.write_text("\n".join([lines[0]] + lines[:0:-1]) + "\n")
        seal(self.actual, "r")
        self.assertEqual(self.compare()["status"], "MATCHED_OUTPUTS")

    def test_same_count_different_ids(self):
        self.change("checkpoint.csv", "1,0,1,", "99,0,1,")
        self.assertNotEqual(self.compare()["status"], "MATCHED_OUTPUTS")

    def test_single_value_mismatch(self):
        self.change("checkpoint.csv", "1,0,1,2,", "1,0,1,2.01,")
        self.assertEqual(self.compare()["status"], "MISMATCH")

    def test_covariance_off_diagonal(self):
        self.change("vcov.csv", "ols,_cons,x,0.01", "ols,_cons,x,0.02")
        self.assertEqual(self.compare()["status"], "MISMATCH")

    def test_integer_fields_exact(self):
        self.change("checkpoint.csv", "1,0,1,", "1,0,1.00000000001,")
        self.assertNotEqual(self.compare()["status"], "MATCHED_OUTPUTS")

    def test_tolerance_boundary(self):
        self.change("checkpoint.csv", "1,0,1,2,", "1,0,1,2.000000001,")
        self.assertEqual(self.compare(atol="0.000000001", rtol="0")["status"], "MATCHED_OUTPUTS")
        self.assertEqual(self.compare(atol="0", rtol="0")["status"], "MISMATCH")

    def test_missing_pattern(self):
        self.change("checkpoint.csv", "1,0,1,2,", "1,0,1,NA,")
        self.assertNotEqual(self.compare()["status"], "MATCHED_OUTPUTS")

    def test_paired_invalid_model_values_never_pass(self):
        for token in ["NA", "NaN", "Inf", ".a"]:
            for folder, engine in [(self.ref, "stata"), (self.actual, "r")]:
                path = folder / "vcov.csv"
                lines = path.read_text().splitlines()
                lines[1] = "ols,_cons,_cons," + token
                path.write_text("\n".join(lines) + "\n")
                seal(folder, engine)
            self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")

    def test_paired_invalid_degrees_of_freedom(self):
        for folder, engine in [(self.ref, "stata"), (self.actual, "r")]:
            path = folder / "statistics.csv"
            path.write_text(path.read_text().replace("cluster,df_r,3", "cluster,df_r,0"))
            seal(folder, engine)
        self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")

    def test_cluster_count_must_match_sample(self):
        self.change("statistics.csv", "cluster,N_clust,4", "cluster,N_clust,5")
        self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")

    def test_duplicate_panel_month(self):
        self.change("checkpoint.csv", "2,0,2,", "2,0,1,")
        self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")

    def test_equivalent_numeric_ids_are_duplicates(self):
        self.change("checkpoint.csv", "2,0,2,", "1.0,0,2,")
        self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")

    def test_missing_normalization_and_tags(self):
        for token in ["", ".", "NA"]:
            self.assertTrue(mod.numeric_equal("NA", token, mod.Decimal(0), mod.Decimal(0)))
        for token in ["NaN", ".a", ".z", "0", "Inf"]:
            self.assertFalse(mod.numeric_equal("NA", token, mod.Decimal(0), mod.Decimal(0)))
        self.assertFalse(mod.numeric_equal(".a", ".b", mod.Decimal(0), mod.Decimal(0)))

    def test_bad_tolerance(self):
        for bad in ["-1", "NaN", "Inf", "garbage"]:
            self.assertEqual(self.compare(atol=bad)["status"], "INVALID_EVIDENCE")

    def test_stale_output_hash(self):
        self.change("checkpoint.csv", "1,0,1,2,", "1,0,1,3,", seal_again=False)
        self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")

    def test_input_hash_mismatch(self):
        p = self.actual / "manifest.json"
        data = json.loads(p.read_text()); data["input_sha256"] = "c" * 64
        p.write_text(json.dumps(data))
        self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")

    def test_wrong_reference_engine(self):
        seal(self.ref, "r")
        self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")

    def test_interpreter_version_is_not_executable_version(self):
        write_csv(self.ref / "runtime.csv", ["key", "value"], [["version_control", "17"]])
        seal(self.ref, "stata")
        self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")

    def test_contradictory_runtime(self):
        p = self.ref / "runtime.csv"
        p.write_text(p.read_text().replace("status,completed", "status,failed"))
        seal(self.ref, "stata")
        self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")

    def test_duplicate_rows(self):
        p = self.actual / "checkpoint.csv"
        p.write_text(p.read_text() + p.read_text().splitlines()[1] + "\n")
        seal(self.actual, "r")
        self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")

    def test_duplicate_header(self):
        self.change("checkpoint.csv", "id,panel,", "id,id,")
        self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")

    def test_empty_table(self):
        p = self.actual / "vcov.csv"
        p.write_text(p.read_text().splitlines()[0] + "\n")
        seal(self.actual, "r")
        self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")

    def test_absent_reference(self):
        self.assertEqual(mod.compare(self.ref / "absent", self.actual)["status"], "REFERENCE_UNAVAILABLE")

    def test_missing_required_file(self):
        (self.actual / "vcov.csv").unlink()
        self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")

    def test_incomplete_covariance(self):
        p = self.actual / "vcov.csv"
        p.write_text("\n".join(p.read_text().splitlines()[:-1]) + "\n")
        seal(self.actual, "r")
        self.assertEqual(self.compare()["status"], "INVALID_EVIDENCE")


if __name__ == "__main__":
    unittest.main()
