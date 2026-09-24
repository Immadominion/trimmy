// A standalone scroll study. Every generated building is a full-frame alpha
// plate, so all twelve share one camera and keep their exact registration.
const route = document.querySelector('.scroll-route');
const plates = [...document.querySelectorAll('.plate')];
const sky = document.querySelector('.sky');
const title = document.querySelector('.title');
const cloud = document.querySelector('.cloud');
const fog = document.querySelector('.fog');
const nextStory = document.querySelector('.next-story');
const cue = document.querySelector('.scroll-cue');
const reduce = window.matchMedia('(prefers-reduced-motion: reduce)');
let raf = 0;

const clamp = value => Math.max(0, Math.min(1, value));
const smooth = value => { const n=clamp(value); return n*n*(3-2*n); };
const range = (value, a, b) => smooth((value-a)/(b-a));

function render(){
  raf=0;
  const total=Math.max(1,route.offsetHeight-window.innerHeight);
  const p=clamp((window.scrollY-route.offsetTop)/total);
  const H=window.innerHeight;
  const climb=range(p,.51,.83);
  const calm=reduce.matches;

  sky.style.transform=`translate3d(0,${(-climb*H*.075).toFixed(2)}px,0) scale(${(1+climb*.045).toFixed(4)})`;
  for(const node of plates){
    const {from,to,rise,rest,push}=node.dataset;
    const assemble=calm?range(p,.04,.32):range(p,+from,+to);
    // Every full-frame plate begins below the viewport, so its image boundary
    // never enters halfway up the sky as a hard rectangular cut.
    const startY=H*((1.04+(+rise)*.17)*(1-assemble)+(+rest||0)*assemble);
    const pushY=H*(+push)*climb;
    const z=node.classList.contains('plate--far')?0:node.classList.contains('plate--mid')?1:2;
    const scale=1+climb*(.018+z*.014);
    node.style.transform=`translate3d(-50%,calc(-50% + ${(startY-pushY).toFixed(2)}px),0) scale(${scale.toFixed(4)})`;
    node.style.setProperty('--edge-feather',`${(12*(1-range(assemble,.88,1))).toFixed(2)}%`);
  }

  title.style.opacity=String(1-range(p,.74,.87));
  title.style.transform=`translate3d(-50%,calc(-50% + ${(-climb*H*.095).toFixed(2)}px),0)`;

  // The cloud overtakes the moving architecture; it is one continuous column.
  const cloudTravel=range(p,.54,.9);
  const cloudY=H*(1.1-cloudTravel*2.05);
  cloud.style.transform=`translate3d(0,${cloudY.toFixed(2)}px,0)`;
  fog.style.opacity=String(range(p,.78,.92));
  const arrival=range(p,.9,.985);
  nextStory.style.opacity=String(arrival);
  nextStory.style.transform=`translate3d(-50%,calc(-45% + ${((1-arrival)*24).toFixed(2)}px),0)`;
  cue.style.opacity=String(1-range(p,.92,.995));
  document.documentElement.dataset.progress=p.toFixed(3);
}

function schedule(){if(!raf)raf=requestAnimationFrame(render)}
window.addEventListener('scroll',schedule,{passive:true});
window.addEventListener('resize',schedule,{passive:true});
reduce.addEventListener('change',schedule);
for(const img of document.images) img.decode?.().then(schedule).catch(()=>{});
schedule();
