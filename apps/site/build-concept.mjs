import {cp,mkdir,rm,stat,writeFile} from 'node:fs/promises';
const source=new URL('./concept/',import.meta.url);
const output=new URL('./concept-dist/',import.meta.url);
const files=['index.html','direction.html','styles.css','plan.css','fluid.css','room-details.css','motion.js','ada-actor.js','ada-rig-data.js','liquid-token.js','paper-flight.js','scroll-scenes.js','room-details.js','activity-feedback.js','activity-feedback.css','assets/mark.png','assets/token.webp','assets/ada-poster.webp','assets/ada-atlas.webp','assets/fonts/BricolageGrotesque-Latin.woff2','assets/fonts/BricolageGrotesque-OFL.txt','assets/fonts/Manrope-Variable.ttf','assets/fonts/Manrope-OFL.txt'];
await rm(output,{recursive:true,force:true});await mkdir(output,{recursive:true});
let bytes=0;
for(const file of files){const target=new URL(file,output);await mkdir(new URL('./',target),{recursive:true});await cp(new URL(file,source),target);bytes+=(await stat(target)).size;}
const config={framework:null,cleanUrls:true,trailingSlash:false,headers:[{source:'/(.*)',headers:[{key:'X-Robots-Tag',value:'noindex, nofollow'},{key:'X-Content-Type-Options',value:'nosniff'},{key:'Referrer-Policy',value:'no-referrer'},{key:'Content-Security-Policy',value:"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; connect-src 'none'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"}]}]};
await writeFile(new URL('vercel.json',output),JSON.stringify(config,null,2)+'\n');
console.log(`Built separate motion study: ${files.length} files, ${bytes} uncompressed bytes. Dedicated review build; public deployment is separate.`);
