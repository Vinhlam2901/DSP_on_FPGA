#!/usr/bin/env python3
"""Compile production RTL with Yosys CXXRTL and compare with existing Python goldens.
Requires Python dependencies from LAB2, Yosys with CXXRTL headers, and g++.
Run from any directory: python3 filter/tests/check_filters.py
"""
from pathlib import Path
import random
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'LAB2_Python/LAB2/python'))
import numpy as np
import quantize
from golden_fir import fir_golden
from golden_iir import iir_golden


def run(args, cwd):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def packed(values, width):
    values = list(map(int, values))
    bits = sum((v & ((1 << width)-1)) << (i*width) for i, v in enumerate(values))
    return f"{len(values)*width}'h{bits:x}"


def check(work, name, h, b, a, wi, wc, ff, fi, guard):
    ns = len(b)
    n = len(h)
    ws = wi + guard
    # Conservative sizes independent of the current coefficient values.
    fa = wi + wc + (n-1).bit_length() + 1
    ia = ws + wc + 3
    defs = [f'module testtop(input clk, rst, valid, input signed [{wi-1}:0] x,',
            'output rfb, rff, rib, rif, vfb, vff, vib, vif,',
            f'output signed [{wi-1}:0] yfb, yff, yib, yif);']
    for kind, suffix in [('fir_baseline','fb'),('fir_folded','ff'),
                         ('iir_baseline','ib'),('iir_folded','if')]:
        if kind.startswith('fir'):
            params = f'.N_TAPS({n}), .F_COEF({ff}), .W_ACC({fa}), .COEFFS({packed(h,wc)})'
        else:
            rows = [v for br, ar in zip(b,a) for v in [*br,*ar]]
            params = (f'.N_SECTIONS({ns}), .F_COEF({fi}), .INPUT_SHIFT({guard}), '
                      f'.W_STATE({ws}), .W_ACC({ia}), .COEFFS({packed(rows,wc)})')
        defs.append(f'{kind} #(.W_IN({wi}), .W_OUT({wi}), .W_COEF({wc}), {params}) '
                    f'd{suffix}(.clk(clk),.rst_n(rst),.in_valid(valid),.in_ready(r{suffix}),'
                    f'.x(x),.out_valid(v{suffix}),.y(y{suffix}));')
    defs.append('endmodule')
    (work/'top.sv').write_text('\n'.join(defs))
    rng = random.Random(42)
    limit = 1 << (wi-1)
    samples = [limit-1]+[0]*30+[-limit,limit-1,-1,1,0]*8
    samples += [rng.randrange(-limit,limit) for _ in range(150)]
    samples += [limit-1]*30 + [-limit]*30 + [0]*1000
    x = np.array(samples, dtype=np.int64)
    yf = (fir_golden(x,h,frac=ff,w_out=wi,w_in=wi) if ff else
          np.clip(np.convolve(x,h)[:len(x)], -limit, limit-1))
    yi = iir_golden(x,b,a,frac=fi,guard=guard,w_state=ws,w_out=wi,w_in=wi)
    (work/'vectors.txt').write_text(''.join(f'{int(u)} {int(f)} {int(i)}\n' for u,f,i in zip(x,yf,yi)))
    script = (f'read_verilog -sv {ROOT}/filter/fir_baseline.sv {ROOT}/filter/fir_folded.sv '
              f'{ROOT}/filter/iir_baseline.sv {ROOT}/filter/iir_folded.sv top.sv; '
              'hierarchy -check -top testtop; proc; opt; check -assert; write_cxxrtl model.cpp')
    run(['yosys','-Q','-T','-p',script],work)
    source = r'''
#include "model.cpp"
#include <fstream>
#include <iostream>
#include <stdexcept>
using namespace cxxrtl_design;
int main() {
  p_testtop d;
  auto setx = [&](int32_t value) { d.p_x.set<uint32_t>(uint32_t(value) & INPUT_MASK); };
  auto tick = [&]() { d.p_clk.set<bool>(false); d.step(); d.p_clk.set<bool>(true); d.step(); d.step(); };
  auto reset = [&]() {
    d.p_valid.set<bool>(false); d.p_rst.set<bool>(false); tick(); tick();
    if (d.p_vfb.get<bool>() || d.p_vff.get<bool>() || d.p_vib.get<bool>() || d.p_vif.get<bool>())
      throw std::runtime_error("valid during reset");
    d.p_rst.set<bool>(true); d.p_clk.set<bool>(false); d.step();
  };
  reset();
  // Abort a transaction before either folded engine finishes, then reset all state.
  setx(123); d.p_valid.set<bool>(true); tick(); reset();
  std::ifstream file("vectors.txt");
  int32_t x, f, i; unsigned sample=0;
  while(file >> x >> f >> i) {
    if (!(d.p_rfb.get<bool>() && d.p_rff.get<bool>() && d.p_rib.get<bool>() && d.p_rif.get<bool>()))
      throw std::runtime_error("not ready at sample start");
    setx(x);
    for (unsigned cycle=0; cycle<SPACING; ++cycle) {
      d.p_valid.set<bool>(cycle==0);
      setx(cycle==0 ? x : (cycle % 2 ? 17 : -19)); tick();
      if (!d.p_rfb.get<bool>() || !d.p_rib.get<bool>() ||
          d.p_rff.get<bool>() != (cycle >= FIR_CYCLES) ||
          d.p_rif.get<bool>() != (cycle >= IIR_CYCLES))
        throw std::runtime_error("wrong ready/busy timing");
      auto verify = [&](bool valid, int32_t value, unsigned due, int32_t expected, const char *name) {
        value &= INPUT_MASK;
        value = (value ^ SIGN_BIT) - SIGN_BIT;
        if(valid != (cycle==due) || (valid && value!=expected)) {
          std::cerr << name << " sample=" << sample << " cycle=" << cycle
                    << " got=" << value << " expected=" << expected << "\n";
          throw std::runtime_error("RTL/golden mismatch or wrong valid latency");
        }
      };
      verify(d.p_vfb.get<bool>(),d.p_yfb.get<int32_t>(),0,f,"fir_baseline");
      verify(d.p_vff.get<bool>(),d.p_yff.get<int32_t>(),FIR_CYCLES,f,"fir_folded");
      verify(d.p_vib.get<bool>(),d.p_yib.get<int32_t>(),0,i,"iir_baseline");
      verify(d.p_vif.get<bool>(),d.p_yif.get<int32_t>(),IIR_CYCLES,i,"iir_folded");
    }
    ++sample;
  }
  // Baselines must also accept a new sample on every clock.
  reset(); file.clear(); file.seekg(0);
  while(file >> x >> f >> i) {
    setx(x); d.p_valid.set<bool>(true); tick();
    auto signed_value = [](uint32_t value) {
      return int32_t(((value & INPUT_MASK) ^ SIGN_BIT)) - SIGN_BIT;
    };
    if (!d.p_vfb.get<bool>() || !d.p_vib.get<bool>() ||
        signed_value(d.p_yfb.get<uint32_t>()) != f ||
        signed_value(d.p_yib.get<uint32_t>()) != i)
      throw std::runtime_error("baseline consecutive samples mismatch");
  }
  std::cout << sample << " samples x 4 variants PASS\n";
}
'''
    (work/'driver.cpp').write_text(source.replace('SPACING',str(max(n,5*ns)+3))
                                  .replace('INPUT_MASK',str((1 << wi)-1)).replace('SIGN_BIT',str(1 << (wi-1))).replace('FIR_CYCLES',str(n)).replace('IIR_CYCLES',str(5*ns)))
    yosys = Path(shutil.which('yosys')).resolve()
    candidates = [yosys.parent.parent/'share/yosys/include', Path('/usr/share/yosys/include')]
    include = next((p for p in candidates if (p/'backends/cxxrtl/runtime/cxxrtl/cxxrtl.h').exists()), None)
    if include is None:
        raise RuntimeError('Yosys CXXRTL development headers not found')
    run(['g++','-std=c++17','-O1',f'-I{include}',f'-I{include}/backends/cxxrtl/runtime','driver.cpp','-o','check'],work)
    print(name + ': ' + run([str(work/'check')],work).strip())


with tempfile.TemporaryDirectory(prefix='filter-check-') as temp:
    work = Path(temp)
    fq, iq = quantize.fir(), quantize.iir()
    check(work,'LAB2 quantized coefficients',fq.h_int,iq.b_int,iq.a_int,24,18,17,16,2)
    # One tap/section, no fractional shift; checks minimum index widths and F=0.
    check(work,'one tap/one section, zero shifts',[1],[[1,0,0]],[[0,0]],8,5,0,0,0)
    # Even tap count, signed coefficients, odd section count, aggressive internal saturation.
    check(work,'signed and saturation cases',[7,-6,5,-4],[[7,6,-5],[6,-5,4]],
          [[-3,1],[-2,1]],8,5,3,3,2)
