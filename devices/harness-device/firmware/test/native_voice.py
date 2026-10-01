"""Link the same voice pack as ESP-IDF into native playback/layout checks."""
from pathlib import Path
import sys

def voice_assets(build):
    main = Path(__file__).resolve().parent / "../main"
    voice = (main / "../../prototype/pro-companion/voice-samples").resolve()
    asm = Path(build) / "voice_pack.s"
    section = ".section __TEXT,__const" if sys.platform == "darwin" else ".section .rodata"
    asm.write_text(section + '\n.globl _binary_pro_voice_pack_start\n.globl _binary_pro_voice_pack_end\n_binary_pro_voice_pack_start:\n.incbin "' + str(voice / "samples.pack") + '"\n_binary_pro_voice_pack_end:\n')
    return [str(main / "pro_voice_samples.c"), str(asm), "-I", str(voice)]
