import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const fixture = process.argv[2] === '--fixture';
const { name, url, digest } = fixture ? {
  name: 'jfk.wav',
  url: 'https://raw.githubusercontent.com/ggml-org/whisper.cpp/v1.8.3/samples/jfk.wav',
  digest: '59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e',
} : {
  name: 'ggml-tiny-q5_1.bin',
  url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/c521a4b02f422512d734391fdf08bb08c0862f68/ggml-tiny-q5_1.bin',
  digest: '818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7',
};

const directory = new URL('../target/voice-models/', import.meta.url);
const target = fileURLToPath(new URL(name, directory));
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

let existing;
try {
  existing = await readFile(target);
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}
if (existing && sha256(existing) === digest) process.exit(0);

const response = await fetch(url, { signal: AbortSignal.timeout(120_000) });
if (!response.ok) throw new Error(`Failed to download ${name} (HTTP ${response.status})`);
const bytes = Buffer.from(await response.arrayBuffer());
if (sha256(bytes) !== digest) throw new Error(`Incorrect SHA-256 for ${name}`);
await mkdir(directory, { recursive: true });
const temporary = `${target}.${randomUUID()}.tmp`;
try {
  await writeFile(temporary, bytes, { flag: 'wx' });
  await rename(temporary, target);
} finally {
  await rm(temporary, { force: true });
}
