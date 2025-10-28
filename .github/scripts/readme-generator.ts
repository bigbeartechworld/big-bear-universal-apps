import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

type App = {
  name: string;
  description: string;
  dockerImage: string;
  version: string;
  youtubeVideo: string;
  docs: string;
  category: string;
  port: string;
};

const getAppsList = async () => {
  const apps: Record<string, App> = {};
  const appsDir = path.join(__dirname, "../../apps");

  try {
    const appDirs = fs
      .readdirSync(appsDir, { withFileTypes: true })
      .filter((dirent: fs.Dirent) => dirent.isDirectory())
      .map((dirent: fs.Dirent) => dirent.name)
      .filter((name: string) => name !== "_example"); // Skip example app

    for (const appDir of appDirs) {
      const appJsonPath = path.join(appsDir, appDir, "app.json");

      if (!fs.existsSync(appJsonPath)) {
        console.warn(`Warning: No app.json found for ${appDir}`);
        continue;
      }

      try {
        const appConfigContent = fs.readFileSync(appJsonPath, "utf8");
        const appConfig = JSON.parse(appConfigContent);

        apps[appDir] = {
          name: appConfig.metadata?.name || appDir,
          description: appConfig.metadata?.description || "N/A",
          dockerImage: appConfig.technical?.main_image || "N/A",
          version: appConfig.metadata?.version || "N/A",
          youtubeVideo: appConfig.resources?.youtube || "",
          docs: appConfig.resources?.documentation || "",
          category: appConfig.metadata?.category || "Uncategorized",
          port: appConfig.technical?.default_port || "N/A",
        };
      } catch (e) {
        const error = e as Error;
        console.error(`Error parsing app.json for ${appDir}:`, error.message);
      }
    }

    console.log(`Successfully loaded ${Object.keys(apps).length} apps`);
  } catch (e) {
    const error = e as Error;
    console.error(`Error reading apps directory:`, error.message);
  }

  return { apps };
};

const appToMarkdownTable = (apps: Record<string, App>) => {
  // Sort apps alphabetically by name
  const sortedApps = Object.values(apps).sort((a, b) =>
    a.name.localeCompare(b.name)
  );

  let table = `| Application | Description | Docker Image | Version | Port | YouTube | Docs |\n`;
  table += `| --- | --- | --- | --- | --- | --- | --- |\n`;

  sortedApps.forEach((app) => {
    // Truncate description if too long
    const desc =
      app.description.length > 100
        ? app.description.substring(0, 97) + "..."
        : app.description;

    const youtubeLink = app.youtubeVideo
      ? `[▶️](${app.youtubeVideo})`
      : "";
    const docsLink = app.docs ? `[📖](${app.docs})` : "";

    table += `| **${app.name}** | ${desc} | \`${app.dockerImage}\` | ${app.version} | ${app.port} | ${youtubeLink} | ${docsLink} |\n`;
  });

  return table;
};

const writeToReadme = (appsTable: string) => {
  const templatePath = path.join(__dirname, "../../templates/README.md");
  const outputPath = path.join(__dirname, "../../README.md");

  const baseReadme = fs.readFileSync(templatePath, "utf8");
  const finalReadme = baseReadme.replace("<!appsList>", appsTable);

  fs.writeFileSync(outputPath, finalReadme);
  console.log(`README.md successfully generated at ${outputPath}`);
};

const main = async () => {
  console.log("Starting README generation...");
  const apps = await getAppsList();
  const markdownTable = appToMarkdownTable(apps.apps);
  writeToReadme(markdownTable);
  console.log(
    `README generation complete! Total apps: ${Object.keys(apps.apps).length}`
  );
};

main();
