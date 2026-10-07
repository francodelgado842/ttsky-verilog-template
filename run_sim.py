"""Run actual Verilog with Icarus + cocotb. Requires Icarus on PATH."""
from pathlib import Path
from cocotb_tools.runner import get_runner
p=Path(__file__).resolve().parent
r=get_runner('icarus')
r.build(sources=[p/'src/project.v',p/'test/tb.v'],hdl_toplevel='tb',build_dir=p/'sim_build',always=True,build_args=['-g2012'])
r.test(hdl_toplevel='tb',test_module='test',test_dir=p/'test',results_xml=p/'results.xml')
