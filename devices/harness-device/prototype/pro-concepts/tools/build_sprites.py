from pathlib import Path
import subprocess

here=Path(__file__).resolve().parent
native=here.parents[2]/'firmware/main/ui/habitat'
out=here.parent/'generated/sprites'
out.mkdir(parents=True,exist_ok=True)
sources=['terminal','fonts','character','character_layout','character_motion','tim','octopus','tux','ascii_clip','octopus_font']
subprocess.run(['cc','-O2','-std=c11','-DHT_FACE_PX=720','-I'+str(native),str(here/'sprites.c'),*[str(native/(s+'.c')) for s in sources],'-o',str(out/'sprites')],check=True)
subprocess.run([str(out/'sprites'),str(out)],check=True)
print('Rendered 48 native character frames')
