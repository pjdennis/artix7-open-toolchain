"""A design that lives outside the kit (e.g. in another repository) and includes its make files."""
import os
import shutil
import subprocess
import tempfile
import unittest

KIT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

FILES = {
    "Makefile": """\
TOP    := top
RTL    := rtl/top.v
XDC    := constr/top.xdc
TB_DIR := sim
include $(FPGA_KIT)/boards/cmod_a7_35t.mk
include $(FPGA_KIT)/mk/sim.mk
include $(FPGA_KIT)/mk/openxc7.mk
""",
    "rtl/top.v": """\
module top #(parameter HALF = 6_000_000) (input sysclk, output reg led = 1'b0);
  reg [$clog2(HALF)-1:0] n = 0;
  always @(posedge sysclk) if (n == HALF - 1) begin n <= 0; led <= ~led; end else n <= n + 1'b1;
endmodule
""",
    "sim/tb_top.v": """\
`include "tb_util.vh"
module tb_top;
  reg clk; wire led;
  top #(.HALF(4)) dut (.sysclk(clk), .led(led));
  `TB_CLOCK(clk, 5, 10000)
  initial begin repeat (5) @(posedge clk); #1 `CHECK_EQ(led, 1'b1, "toggled") `TB_PASS end
endmodule
""",
    "constr/top.xdc": """\
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports {sysclk}]
set_property -dict { PACKAGE_PIN A17 IOSTANDARD LVCMOS33 } [get_ports {led}]
""",
}


class ExternalDesignTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.design = os.path.join(cls.tmp, "design")
        for path, text in FILES.items():
            full = os.path.join(cls.design, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as f:
                f.write(text)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def make(self, *args, **env):
        e = {k: v for k, v in os.environ.items() if k != "XDG_CACHE_HOME"}
        # HOME is redirected to keep flash backups out of the real cache; the toolchain stays put.
        e.setdefault("FPGA_PREFIX", os.path.expanduser("~/opt/fpga"))
        e.update(FPGA_KIT=KIT, HOME=os.path.join(self.tmp, "home"), **env)
        return subprocess.run(["make", "-C", self.design, *args], env=e, capture_output=True, text=True)

    def test_env_sh_exports_kit_location(self):
        out = subprocess.run(["bash", "-c", f"source {KIT}/env.sh && echo $FPGA_KIT"], capture_output=True, text=True)
        self.assertEqual(out.stdout.strip(), KIT)

    def test_simulation(self):
        r = self.make("test")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("PASS", r.stdout)

    def test_flash_backups_go_to_the_user_cache_not_a_repository(self):
        r = self.make("-n", "flash")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(os.path.join(self.tmp, "home", ".cache", "fpga-flash-backups", "cmoda7_35t-first.bin"), r.stdout)
        self.assertNotIn(KIT + "/flash-backups", r.stdout)

    def test_flash_backups_respect_xdg_cache_home(self):
        r = self.make("-n", "flash", XDG_CACHE_HOME=os.path.join(self.tmp, "xdg"))
        self.assertIn(os.path.join(self.tmp, "xdg", "fpga-flash-backups", "cmoda7_35t-first.bin"), r.stdout)

    def test_bitstream_build_records_kit_version(self):
        r = self.make("bit")
        self.assertEqual(r.returncode, 0, r.stdout[-2000:] + r.stderr[-2000:])
        with open(os.path.join(self.design, "build", "KIT_VERSION")) as f:
            text = f.read()
        head = subprocess.run(["git", "-C", KIT, "rev-parse", "--short=12", "HEAD"],
                              capture_output=True, text=True).stdout.strip()
        self.assertTrue(text.startswith(f"kit {head}"), text)
        with open(os.path.join(KIT, "TOOLCHAIN_VERSIONS")) as f:
            self.assertIn(f.read(), text)


if __name__ == "__main__":
    unittest.main()
