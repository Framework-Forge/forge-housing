<script lang="ts">
 import {onDestroy} from 'svelte';
 const sounds=new Map<string,HTMLAudioElement>();
 function receive(event:MessageEvent){const d=event.data;if(d?.action!=='hygieneAudio'||!['shower','flush'].includes(d.name))return;let audio=sounds.get(d.name);if(d.stop){if(audio){audio.pause();audio.currentTime=0;}return;}if(!audio){audio=new Audio(`https://cfx-nui-forge-housing/audio/${d.name}.ogg`);sounds.set(d.name,audio);}audio.volume=.25;audio.loop=d.name==='shower';void audio.play().catch(()=>{});}
 onDestroy(()=>sounds.forEach(a=>a.pause()));
</script>
<svelte:window on:message={receive}/>
