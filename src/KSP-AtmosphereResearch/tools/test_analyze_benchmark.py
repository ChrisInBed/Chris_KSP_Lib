import math,unittest
from analyze_benchmark import summarize_timings,summarize_parity
class BenchmarkAnalysisTests(unittest.TestCase):
    def test_timings_weight_calls_and_mark_errors(self):
        common={'mode':'managed_hermite','workers':'1','allocated_bytes':'-1','determinism_mismatches':'0','max_density_relative_difference':'0','max_temperature_difference_k':'0','error':''}
        rows=[dict(common,calls='100',elapsed_ms='1',ns_per_call='10000'),dict(common,calls='900',elapsed_ms='1',ns_per_call=str(1e6/900)),dict(common,calls='0',elapsed_ms='0',ns_per_call='NaN',error='test fault')]
        r=summarize_timings(rows)[0];self.assertEqual(r['weighted_ns_per_call'],2000);self.assertEqual(r['errors'],1);self.assertTrue(math.isnan(r['bytes_per_call']))
    def test_parity_filters_thin_air_and_audits_vacuum(self):
        common={'mode':'test','status':'finite','native_pressure_pa':'1000','native_temperature_k':'300','native_density_kg_m3':'1','snapshot_pressure_pa':'1000','snapshot_density_kg_m3':'1','density_relative_error':'.00002','temperature_error_k':'.001','pressure_error_pa':'0'}
        rows=[common,dict(common,native_density_kg_m3='1e-10',density_relative_error='9'),dict(common,native_pressure_pa='0',native_temperature_k='0',native_density_kg_m3='0',snapshot_pressure_pa='0',snapshot_density_kg_m3='1',density_relative_error='NaN')]
        r=summarize_parity(rows)[0];self.assertEqual(r['ranked_density_rows'],1);self.assertAlmostEqual(r['density_max_abs_percent'],.002);self.assertEqual(r['vacuum_nonzero'],1)
    def test_zero_pressure_below_boundary_is_not_vacuum(self):
        r=summarize_parity([{'mode':'thin','status':'finite','native_pressure_pa':'0','native_temperature_k':'550','native_density_kg_m3':'0','density_relative_error':'NaN','temperature_error_k':'0.000061','pressure_error_pa':'1e-11','snapshot_density_kg_m3':'7e-17','snapshot_pressure_pa':'1e-11'}])[0]
        self.assertEqual(r['vacuum_nonzero'],0);self.assertEqual(r['air_rows'],1);self.assertEqual(r['ranked_density_rows'],0)
        self.assertAlmostEqual(r['temperature_max_abs_k'],0.000061)
    def test_nonfinite_temperature_does_not_pass(self):
        r=summarize_parity([{'mode':'bad','status':'invalid','native_pressure_pa':'1000','native_temperature_k':'300','native_density_kg_m3':'1','density_relative_error':'NaN','temperature_error_k':'NaN','pressure_error_pa':'NaN','snapshot_density_kg_m3':'NaN','snapshot_pressure_pa':'NaN'}])[0]
        self.assertEqual(r['invalid'],1);self.assertEqual(r['temperature_max_abs_k'],math.inf)
if __name__=='__main__':unittest.main()
