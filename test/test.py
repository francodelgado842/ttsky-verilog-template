"""Cocotb: arithmetic, protocol and actual CH0 recordings, no external packages."""
from pathlib import Path
import random
import cocotb
from cocotb.triggers import Timer

class Host:
    def __init__(self,d):self.d=d
    async def tick(self):
        # One 1 us cycle (1 MHz); allow propagation in gate-level simulation.
        self.d.clk.value=0;await Timer(250,unit='ns')
        self.d.clk.value=1;await Timer(500,unit='ns')
        self.d.clk.value=0;await Timer(250,unit='ns')
    async def reset(self):
        self.d.ena.value=1;self.d.ui_in.value=0;self.d.uio_in.value=0;self.d.rst_n.value=0
        await self.tick();await self.tick();self.d.rst_n.value=1;await self.tick()
        assert self.d.uio_oe.value.is_resolvable, (
            f'uio_oe={self.d.uio_oe.value}: unknown bits after reset; '
            'check GL_TEST power connections VPWR=1 and VGND=0 in tb.v'
        )
        assert int(self.d.uio_oe.value)==0xE0
        assert int(self.d.uio_out.value)==0
    async def write(self,b,cmd=False,hold=1):
        self.d.uio_in.value=2 if cmd else 0;self.d.ui_in.value=b;await self.tick()
        old=(int(self.d.uio_out.value)>>7)&1
        self.d.uio_in.value=3 if cmd else 1
        for _ in range(hold):await self.tick()
        assert ((int(self.d.uio_out.value)>>7)&1)==1-old
        self.d.uio_in.value=0;await self.tick()
    async def word(self,addr,value):
        await self.write(addr,True);await self.write(value&255);await self.write(value>>8)
    async def snapshot(self):await self.write(4,True)
    async def read(self,view):
        self.d.uio_in.value=view<<2;await self.tick();lo=int(self.d.uo_out.value)
        self.d.uio_in.value=(view<<2)|16;await self.tick();hi=int(self.d.uo_out.value)
        self.d.uio_in.value=0
        return lo|(hi<<8)
    async def config(self,off,lo,hi):
        # Temporary upper limit permits either direction of threshold change.
        await self.word(3,4095);await self.word(2,lo);await self.word(3,hi);await self.word(1,off)
    async def sample(self,x):await self.word(0,x)
    async def block(self,x,expected,active):
        old=(int(self.d.uio_out.value)>>6)&1
        for i in range(64):
            await self.sample(x)
            if i<63:assert ((int(self.d.uio_out.value)>>6)&1)==old
        assert ((int(self.d.uio_out.value)>>6)&1)==1-old
        await self.snapshot();assert await self.read(2)==expected
        assert (int(self.d.uio_out.value)>>5)&1==active

@cocotb.test()
async def test_mav_protocol_and_real_emg(dut):
    h=Host(dut);await h.reset()
    # Hysteresis including equality and minimum/maximum codes.
    for amp,active in [(8,0),(16,0),(17,1),(16,1),(10,1),(9,0)]:
        await h.block(1995+amp,amp,active)
    await h.config(4095,10,16);await h.block(0,4095,1)
    await h.snapshot();assert await h.read(0)==((-4095)&65535);assert await h.read(1)==4095
    await h.config(0,10,16);await h.block(4095,4095,1)
    # Partial block dropped on configuration, final sample included.
    await h.config(1995,10,16)
    for _ in range(63):await h.sample(4095)
    await h.word(1,1995)
    for _ in range(63):await h.sample(1995)
    await h.snapshot();assert (await h.read(3))&2==0
    await h.sample(2059);await h.snapshot();assert await h.read(2)==1
    # Incomplete sample cancelled by a new command; malformed high byte rejected.
    await h.reset();await h.write(0,True);await h.write(255)
    await h.snapshot();assert await h.read(0)==0
    await h.write(0,True);await h.write(255);await h.write(0x10)
    await h.snapshot();assert (await h.read(3))&4;assert await h.read(1)==0
    await h.write(5,True);await h.write(88) # unexpected data -> error
    await h.snapshot();assert (await h.read(3))&4
    await h.write(5,True);await h.word(2,16) # low >= high invalid
    await h.snapshot();assert (await h.read(3))&4
    await h.write(5,True);await h.word(3,10) # high <= low invalid
    await h.snapshot();assert (await h.read(3))&4
    await h.write(5,True);await h.write(99,True)
    await h.snapshot();assert (await h.read(3))&4
    await h.reset();await h.write(0,True);await h.write(1995&255);await h.write(1995>>8,hold=5)
    await h.snapshot();assert await h.read(3)==0 # only one sample accepted, no spurious error
    # Snapshot remains stable while new samples arrive.
    await h.sample(1900);await h.snapshot();old=await h.read(0)
    await h.sample(2000);assert await h.read(0)==old
    await h.snapshot();assert await h.read(0)==5
    # Disabled WRITE produces neither data nor an acknowledgement on re-enable.
    await h.reset();dut.ena.value=0;dut.uio_in.value=3;dut.ui_in.value=0;await h.tick()
    dut.ena.value=1;await h.tick();assert int(dut.uio_out.value)==0
    dut.uio_in.value=0;await h.tick()
    # Seeded random data vs independent integer Python arithmetic.
    await h.config(2037,400,650);rng=random.Random(842);state=0
    for _ in range(30):
        values=[rng.randrange(4096) for _ in range(64)]
        expected=sum(abs(x-2037) for x in values)//64
        if expected>650:state=1
        elif expected<400:state=0
        for x in values:await h.sample(x)
        await h.snapshot();assert await h.read(2)==expected
        assert (int(dut.uio_out.value)>>5)&1==state
    # Two complete actual recordings, evaluated separately because of recording gap.
    results={}
    for name in ['reposo_ch0.hex','cierre_ch0.hex']:
        await h.reset();values=[int(s,16) for s in (Path(__file__).parent/name).read_text().split()]
        state=0;predictions=[]
        for start in range(0,len(values),64):
            block=values[start:start+64];expected=sum(abs(x-1995) for x in block)//64
            if expected>16:state=1
            elif expected<10:state=0
            for x in block:await h.sample(x)
            await h.snapshot();assert await h.read(2)==expected
            assert await h.read(0)==((block[-1]-1995)&65535)
            assert await h.read(1)==abs(block[-1]-1995)
            assert await h.read(3)==(2|state)
            predictions.append(state)
        results[name]=dict(samples=len(values),windows=len(predictions),active_windows=sum(predictions))
    dut._log.info('Real recordings exact agreement: %s',results)
