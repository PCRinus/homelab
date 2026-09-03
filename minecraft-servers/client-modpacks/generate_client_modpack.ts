import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import AdmZip from 'adm-zip';

type LoaderVersion = {
  loader?: {
    stable?: boolean;
    version?: string;
  };
};

type ProjectInfo = {
  client_side?: 'required' | 'optional' | 'unsupported' | 'unknown';
};

type VersionFile = {
  primary?: boolean;
  filename?: string;
  hashes?: Record<string, string>;
  url?: string;
  size?: number;
};

type ProjectVersion = {
  files?: VersionFile[];
};

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const serversDir = path.resolve(scriptDir, '..');
const outDir = process.env.MODPACK_OUTPUT_DIR
  ? path.resolve(process.env.MODPACK_OUTPUT_DIR)
  : scriptDir;
const resolvedEnvPath = process.env.MODRINTH_RESOLVED_ENV
  ? path.resolve(process.env.MODRINTH_RESOLVED_ENV)
  : '/tmp/world-generation-mods.env';
const projectsVariable = process.env.MODRINTH_PROJECTS_VARIABLE
  ?? 'MODRINTH_PROJECTS_WORLD_GENERATION';
const packSlug = process.env.MODPACK_SLUG ?? 'modded-client';
const packName = process.env.MODPACK_NAME ?? 'Modded Friends Client Pack';

const envText = await readFile(resolvedEnvPath, 'utf8');
const mcMatch = envText.match(/GENERATED_MC_VERSION='([^']+)'/);
const modsMatch = envText.match(new RegExp(`${projectsVariable}='([^']+)'`));

if (!mcMatch || !modsMatch) {
  throw new Error(`Could not parse ${resolvedEnvPath} for ${projectsVariable}`);
}

const mcVersion = mcMatch[1];
const entries = modsMatch[1].split(',').map((item) => item.trim()).filter(Boolean);
const slugToVersion = new Map<string, string>();

for (const entry of entries) {
  const [slug, versionId] = entry.split(':', 2);
  if (slug && versionId) {
    slugToVersion.set(slug, versionId);
  }
}

async function fetchJson<T>(url: string): Promise<T> {
  const response = await fetch(url, {
    headers: { 'User-Agent': 'mircea-homelab-client-modpack/1.0' },
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} for ${url}`);
  }
  return (await response.json()) as T;
}

const loaderCandidates = await fetchJson<LoaderVersion[]>(
  `https://meta.fabricmc.net/v2/versions/loader/${mcVersion}`,
);
const stableLoader = loaderCandidates.find((item) => item.loader?.stable && item.loader.version)
  ?? loaderCandidates.find((item) => item.loader?.version);
const loaderVersion = stableLoader?.loader?.version;

if (!loaderVersion) {
  throw new Error(`No Fabric loader found for Minecraft ${mcVersion}`);
}

const files: Array<{
  path: string;
  hashes: Record<string, string>;
  env: { client: 'required'; server: 'unsupported' };
  downloads: string[];
  fileSize: number;
}> = [];
const clientJars: Array<{ filename: string; url: string }> = [];
const excluded: string[] = [];

for (const [slug, versionId] of [...slugToVersion.entries()].sort(([a], [b]) => a.localeCompare(b))) {
  const project = await fetchJson<ProjectInfo>(`https://api.modrinth.com/v2/project/${slug}`);

  if (project.client_side === 'unsupported') {
    excluded.push(slug);
    continue;
  }

  const version = await fetchJson<ProjectVersion>(
    `https://api.modrinth.com/v2/project/${slug}/version/${versionId}`,
  );
  const primary = version.files?.find((item) => item.primary) ?? version.files?.[0];

  if (!primary?.filename || !primary.url || typeof primary.size !== 'number') {
    throw new Error(`No primary file for ${slug}:${versionId}`);
  }

  const hashes = Object.fromEntries(
    Object.entries(primary.hashes ?? {}).filter(([key]) => key === 'sha1' || key === 'sha512'),
  );

  if (Object.keys(hashes).length === 0) {
    throw new Error(`Missing hashes for ${slug}:${versionId}`);
  }

  files.push({
    path: `mods/${primary.filename}`,
    hashes,
    env: { client: 'required', server: 'unsupported' },
    downloads: [primary.url],
    fileSize: primary.size,
  });
  clientJars.push({ filename: primary.filename, url: primary.url });
}

const dateStamp = new Date().toISOString().slice(0, 10).replaceAll('-', '');
const artifactBase = `${packSlug}-${mcVersion}`;
const index = {
  formatVersion: 1,
  game: 'minecraft',
  versionId: `${artifactBase}-${dateStamp}`,
  name: `${packName} (${mcVersion})`,
  summary: `Client pack generated from ${projectsVariable} for Minecraft ${mcVersion}.`,
  files,
  dependencies: {
    minecraft: mcVersion,
    'fabric-loader': loaderVersion,
  },
};

await mkdir(outDir, { recursive: true });

const indexPath = path.join(outDir, `${artifactBase}.modrinth.index.json`);
await writeFile(indexPath, `${JSON.stringify(index, null, 2)}\n`, 'utf8');

const mrpackPath = path.join(outDir, `${artifactBase}.mrpack`);
const mrpack = new AdmZip();
mrpack.addFile('modrinth.index.json', Buffer.from(JSON.stringify(index), 'utf8'));
mrpack.writeZip(mrpackPath);

const jarsZipPath = path.join(outDir, `${artifactBase}-mods.zip`);
const jarsZip = new AdmZip();

for (const jar of clientJars) {
  const response = await fetch(jar.url, { signal: AbortSignal.timeout(120_000) });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} while downloading ${jar.url}`);
  }
  jarsZip.addFile(`mods/${jar.filename}`, Buffer.from(await response.arrayBuffer()));
}

jarsZip.addFile('modrinth.index.json', Buffer.from(`${JSON.stringify(index, null, 2)}\n`, 'utf8'));
jarsZip.writeZip(jarsZipPath);

const reportPath = path.join(outDir, `${artifactBase}.excluded-server-only.txt`);
await writeFile(reportPath, excluded.length > 0 ? `${excluded.join('\n')}\n` : '', 'utf8');

console.log(mrpackPath);
console.log(jarsZipPath);
console.log(indexPath);
console.log(reportPath);
console.log(
  `files=${files.length} excluded=${excluded.length} resolved=${slugToVersion.size} `
  + `mc=${mcVersion} fabric-loader=${loaderVersion} source=${serversDir}`,
);
