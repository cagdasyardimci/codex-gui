// Rebuild the offline ELK adapter; npm dependencies are needed only when updating this resource.
import * as esbuild from 'esbuild';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = dirname(fileURLToPath(import.meta.url));
const resources = resolve(directory, '../../Sources/CodexGUI/Resources/Mermaid');
let adaptedModules = 0;
const result = await esbuild.build({
    absWorkingDir: directory,
    entryPoints: ['node_modules/@mermaid-js/layout-elk/dist/mermaid-layout-elk.core.mjs'],
    bundle: true,
    format: 'iife',
    globalName: 'markdownElkLayouts',
    minify: true,
    target: 'safari17',
    outfile: resolve(resources, 'elk.min.js'),
    metafile: true,
    write: false,
    plugins: [{
        name: 'markdown-elk-root-spacing',
        setup(build) {
            build.onLoad({
                filter: /[/\\]@mermaid-js[/\\]layout-elk[/\\]dist[/\\]chunks[/\\]mermaid-layout-elk\.core[/\\]render-[^/\\]+\.mjs$/
            }, async ({ path }) => {
                const source = await readFile(path, 'utf8');
                const upstream = '"spacing.baseValue": 35';
                if (source.split(upstream).length - 1 !== 1) {
                    throw new Error('Pinned ELK adapter must contain exactly one root spacing value of 35.');
                }
                adaptedModules += 1;
                // Match the reference connector spacing; retain the separate cluster value of 30.
                return {
                    contents: source.replace(upstream, '"spacing.baseValue": 40'),
                    loader: 'js',
                    resolveDir: dirname(path)
                };
            });
        }
    }]
});
if (adaptedModules !== 1) {
    throw new Error(`Expected exactly one pinned ELK layout module; found ${adaptedModules}.`);
}
const packages = new Set(Object.keys(result.metafile.inputs).flatMap(input => {
    const match = input.match(/^(.*node_modules\/(?:@[^/]+\/)?[^/]+)\//);
    return match ? [match[1]] : [];
}));
const notices = [];
for (const name of [...packages].sort()) {
    const path = resolve(directory, name);
    const metadata = JSON.parse(await readFile(resolve(path, 'package.json'), 'utf8'));
    notices.push(`${metadata.name}@${metadata.version}\n${JSON.stringify(metadata.repository ?? '')}\n`);
    for (const file of (await readdir(path)).filter(file => /^(LICENSE|COPYING)/i.test(file)).sort()) {
        notices.push(await readFile(resolve(path, file), 'utf8'));
    }
}
for (const output of result.outputFiles) {
    await writeFile(output.path, output.contents);
}
await writeFile(resolve(resources, 'ELK-LICENSES.txt'), notices.join('\n\n--------------------\n\n'));
