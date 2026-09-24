# Wall Street opening: separate-image study

This is an independent visual experiment for the 1653 opening. It does not
modify `site-v2`. Run `npm run dev` in this directory, then visit
`http://localhost:5174/`. `npm run build` writes this study's own `dist/`.

Twelve transparent architectural plates were generated with the built-in
imagegen tool, all using the existing upward-looking Wall Street photograph
as the strict camera and lighting reference. The central flag and its pole
were separated into their own thirteenth plate so they can sit in front of
the tower but behind the Federal Hall pediment. The existing sky and cloud are reused for
continuity with the current landing page. The master imagery and generated
plates are saved in `public/assets/`, not loaded from an external service.

The scroll stages the buildings individually into the same registered frame,
then gives near buildings a slightly longer climb than the distant ones. The
year and headline are live text centered in the sky, behind the near architecture.
The cloud passage leads into the existing 1790 copy so the upward direction
can be judged rather than ending abruptly.

## Imagegen prompt set

Use case: `background-extraction`. The shared instruction for each plate:

> The attached upward Wall Street photograph is a strict camera, silhouette,
> position, scale, lighting and facade reference. Keep the entire 16:10 original
> frame and make all pixels except the requested one building genuinely
> transparent alpha. Photorealistic stone, true foreshortening, consistent warm
> late-afternoon light, crisp windows and masonry. No sky, backdrop, neighboring
> buildings, text, or new viewpoint.

Individual subjects: top-left overhang; broad left midground office facade;
near left foreground facade; left gridded tower; left narrow background tower;
central pale tower with realistic U.S. flag and pole; Federal Hall pediment;
right background gold office tower; center-right striped tower; dark right
foreground tower; near right stone facade with sunlight band; top-right overhang.

Targeted edits removed unwanted neighboring geometry from the broad left
facade and split the flag from its tower. Those edits preserve the shared
camera and alpha.
