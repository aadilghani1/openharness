// Explicit, paid generation of the 16 review clips. Never runs on the device or during build.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const require=createRequire(new URL('../../../../../cli/package.json', import.meta.url));
const WebSocket=require('ws');
const output=process.argv.find(a=>a.startsWith('--output='))?.slice(9);
if(!output)throw Error('Pass --output=/absolute/path');
const original=process.argv.find(a=>a.startsWith('--original='))?.slice(11);
const dir=output+'/audio';
await mkdir(dir,{recursive:true,mode:0o700});
const {stdout}=process.env.ELEVENLABS_API_KEY ? {stdout:process.env.ELEVENLABS_API_KEY} : await promisify(execFile)('/usr/bin/security',['find-generic-password','-s','harness.creature-voice.elevenlabs','-a','elevenlabs-d-test','-w']);
const key=stdout.trim();
const spark='3FdYdVW35CMYTazwp3E1';
const phrase="I'm here with you. What shall we make next?";
const rows=[];
function add(id,voice,title,tag,caption,note,extra={}) {
  rows.push({id,voice,title,tag,caption,note,voice_id:spark,model_id:'eleven_v4',stability:0.5,similarity_boost:0.75,seed:1363,...extra});
}
add('spark-original','Spark','Original excited','excited, contained voice',"Ooh, there you are! I've got eight arms and a very good feeling about this. What are we making next?",'The same original clip used in our speaker test.',{model_id:'eleven_v4_turbo',seed:null,reuse:original});
add('spark-playful','Spark','Playful baseline','playful',phrase,'Baseline for the voice, model and tuning comparisons.');
add('jessica-playful','Jessica','Bright and warm','playful',phrase,'Same words and settings; a different voice.',{voice_id:'cgSgspJ2msm6clMCkdW9'});
add('callum-playful','Callum','Husky trickster','playful',phrase,'Same words and settings; a different voice.',{voice_id:'N2lVS1w4EtoT3dr4eOWO'});
add('spark-happy','Spark','Happy','happy','Good news! Everything is ready. Let\'s make something wonderful.','Listen for warmth and a smile in the delivery.');
add('spark-excited','Spark','Excited','excited','It worked! Eight arms in the air. We did it!','Listen for energy, pitch movement and emphasis.');
add('spark-curious','Spark','Curious','curious',"Ooh, what's this? I think we're onto something.",'Listen for an inquisitive rise and playful pacing.');
add('spark-sad','Spark','Sad','sad',"Oh... that didn't work. I'm here. We'll try again together.",'A gentle response to disappointment.');
add('spark-angry','Spark','Angry at the glitch','angry',"That stubborn glitch is back. Right, let's fix it!",'Frustration aimed at a problem, never at you.');
add('spark-whisper','Spark','Whisper','whispers',"Psst... I've got a little idea. Come closer.",'Quiet delivery; use volume to compare speaker detail.');
add('spark-laugh','Spark','Laugh','laughs',"Eight arms, and I still dropped it. Let's try again!",'A nonverbal reaction tag before spoken words.');
add('spark-creative','Spark','Stability: 0','playful',phrase,'Lower stability: more varied, expressive performance.',{stability:0});
add('spark-steady','Spark','Stability: 1','playful',phrase,'Higher stability: a more consistent performance.',{stability:1});
add('spark-loose','Spark','Similarity: 0.25','playful',phrase,'Less strict adherence to the reference voice.',{similarity_boost:0.25});
add('spark-close','Spark','Similarity: 1','playful',phrase,'Closer adherence to the reference voice.',{similarity_boost:1});
add('spark-turbo','Spark','Turbo comparison','playful',phrase,'Same words, voice and settings as the v4 baseline.',{model_id:'eleven_v4_turbo',seed:null});
async function turbo(row) {
 return new Promise((resolve,reject)=>{
  let finished=false;const parts=[];let bytes=0;
  const ws=new WebSocket('wss://api.elevenlabs.io/v1/text-to-dialogue/stream-input?model_id=eleven_v4_turbo&output_format=pcm_16000',{headers:{'xi-api-key':key},handshakeTimeout:15000,followRedirects:false,maxPayload:1500000});
  const done=(error)=>{if(finished)return;finished=true;clearTimeout(timer);ws.terminate();error?reject(new Error(error)):resolve(Buffer.concat(parts));};
  const timer=setTimeout(()=>done('Turbo timed out'),45000);
  ws.on('open',()=>{ws.send(JSON.stringify({voices:[row.voice_id],voice_settings:{stability:row.stability,similarity_boost:row.similarity_boost}}));ws.send(JSON.stringify({inputs:[{text:row.text,voice_id:row.voice_id}]}));ws.send(JSON.stringify({close_socket:true}));});
  ws.on('message',data=>{try{const v=JSON.parse(data.toString());if(v.error||v.type==='error')return done('Turbo rejected request');if(v.audio){const b=Buffer.from(v.audio,'base64');parts.push(b);bytes+=b.length;if(bytes>400000)return done('Turbo audio too long');}if(v.is_final===true)done();}catch{done('Turbo protocol error');}});
  ws.on('error',()=>done('Turbo connection failed'));ws.on('close',()=>{if(!finished)done('Turbo stream incomplete');});
 });
}
for (const row of rows) {
 row.text=`[${row.tag}] ${row.caption}`;row.output_format='pcm_16000';row.sample_rate=16000;row.channels=1;
 let pcm;let cached=false;const path=dir+'/'+row.id+'.pcm';
 try{pcm=await readFile(path);cached=true;}catch{}
 const begin=Date.now();
 if(!pcm){
  if(row.id==='spark-original'&&!row.reuse)throw Error('Pass --original=/path/to/the/saved/octo-spark.pcm');
  if(row.reuse)pcm=await readFile(row.reuse);
  else if(row.model_id==='eleven_v4_turbo')pcm=await turbo(row);
  else {
   const payload={text:row.text,model_id:row.model_id,voice_settings:{stability:row.stability,similarity_boost:row.similarity_boost},seed:row.seed,language_code:'en',apply_text_normalization:'auto'};
   const r=await fetch('https://api.elevenlabs.io/v1/text-to-speech/'+row.voice_id+'/stream?output_format=pcm_16000',{method:'POST',redirect:'error',headers:{'xi-api-key':key,'Content-Type':'application/json'},body:JSON.stringify(payload),signal:AbortSignal.timeout(45000)});
   if(!r.ok)throw Error(row.id+': provider HTTP '+r.status);
   pcm=Buffer.from(await r.arrayBuffer());
  }
  if(!pcm.length||pcm.length%2||pcm.length>384000)throw Error(row.id+': invalid PCM length');
  await writeFile(path,pcm,{mode:0o600});
 }
 row.samples=pcm.length/2;row.seconds=row.samples/16000;row.sha256=createHash('sha256').update(pcm).digest('hex');row.pcm_file=row.id+'.pcm';
 row.language_code=row.model_id==='eleven_v4'?'en':'auto';row.apply_text_normalization=row.model_id==='eleven_v4'?'auto':'provider default';
 delete row.reuse;
 await writeFile(output+'/samples.json',JSON.stringify(rows.filter(r=>r.samples),null,2)+'\n');
 console.log(`${row.id}: ${row.seconds.toFixed(2)}s (${cached?'cached':Date.now()-begin+'ms'})`);
}
console.log('Complete: '+rows.length+' samples, '+rows.reduce((n,r)=>n+r.seconds,0).toFixed(2)+' seconds');
