import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const packageJsonPath = path.resolve(__dirname, '../package.json');

try {
    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
    const currentVersion = packageJson.version;

    // Split version into parts (supports x.y.z.w format)
    const parts = currentVersion.split('.').map(Number);

    // Increment the last part
    parts[parts.length - 1]++;

    const newVersion = parts.join('.');
    packageJson.version = newVersion;

    fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson, null, 2) + '\n');

    console.log(`Version bumped from ${currentVersion} to ${newVersion}`);
} catch (error) {
    console.error('Error bumping version:', error);
    process.exit(1);
}
