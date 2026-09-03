import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const backendRoot = path.resolve(scriptDirectory, '..');
const webRoot = path.resolve(backendRoot, '..', 'web');
const viteEntry = path.join(webRoot, 'node_modules', 'vite', 'dist', 'node', 'index.js');

const { createServer } = await import(pathToFileURL(viteEntry).href);
const server = await createServer({
  root: webRoot,
  appType: 'custom',
  logLevel: 'error',
  server: { middlewareMode: true },
});

try {
  const [candidateModule, questionModule, sourceModule, configModule] =
    await Promise.all([
      server.ssrLoadModule('/data/candidates.ts'),
      server.ssrLoadModule('/data/questions.ts'),
      server.ssrLoadModule('/data/sources.ts'),
      server.ssrLoadModule('/data/config.ts'),
    ]);

  const sourceThemeCorrections = new Map([
    ['brun-program-2026', ['Europe']],
    ['guedj-program-2026', ['Institutions', 'Écologie & énergie']],
  ]);

  const sources = sourceModule.sources.map((source) => ({
    ...source,
    themes: [
      ...new Set([
        ...source.themes,
        ...(sourceThemeCorrections.get(source.id) ?? []),
      ]),
    ],
  }));

  const content = {
    importedAt: '2026-09-03',
    dataVersion: configModule.DATA_VERSION,
    minComparableAnswers: configModule.MIN_COMPARABLE_ANSWERS,
    themes: questionModule.themes,
    candidates: candidateModule.candidates,
    questions: questionModule.questions,
    sources,
  };

  const outputDirectory = path.join(backendRoot, 'content');
  await mkdir(outputDirectory, { recursive: true });
  await writeFile(
    path.join(outputDirectory, 'editorial-content.json'),
    `${JSON.stringify(content, null, 2)}\n`,
    'utf8',
  );
} finally {
  await server.close();
}
