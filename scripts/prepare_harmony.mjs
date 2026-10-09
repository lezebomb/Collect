import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const app = path.join(root, 'harmony', 'app');
await fs.mkdir(app, { recursive: true });
const profile = path.join(app, 'ohos', 'build-profile.json5');
try { await fs.access(profile); } catch {
  await fs.copyFile(path.join(app, 'ohos', 'build-profile.template.json5'), profile);
}
for (const folder of ['lib', 'test']) {
  await fs.cp(path.join(root, folder), path.join(app, folder), { recursive: true });
}
for (const name of ['pubspec.yaml']) {
  await fs.copyFile(path.join(root, 'harmony', name), path.join(app, name));
}
await fs.copyFile(path.join(root, 'analysis_options.yaml'), path.join(app, 'analysis_options.yaml'));

async function adapt(directory) {
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) await adapt(file);
    else if (entry.name.endsWith('.dart')) {
      const source = await fs.readFile(file, 'utf8');
      let adapted = source
        .replaceAll('package:image_picker/image_picker.dart', 'package:shou_cang_gui/harmony_media.dart')
        .replaceAll('package:file_picker/file_picker.dart', 'package:shou_cang_gui/harmony_media.dart');
      if (entry.name === 'app_theme.dart') adapted = adapted.replace(
        /import 'package:flutter\/cupertino.dart'[^;]*;\r?\n/, '');
      if (entry.name === 'settings_screen.dart') adapted = adapted.replace(
        'length != null && length > ItemListImport.maxFileBytes',
        'length > ItemListImport.maxFileBytes');
      const imports = new Set();
      adapted = adapted.split('\n').filter(line => {
        if (!line.startsWith('import ')) return true;
        if (imports.has(line.trim())) return false;
        imports.add(line.trim());
        return true;
      }).join('\n');
      await fs.writeFile(file, adapted);
    }
  }
}
await adapt(path.join(app, 'lib'));
await adapt(path.join(app, 'test'));
await fs.cp(path.join(root, 'harmony', 'test'), path.join(app, 'test'), { recursive: true });
const generatedTest = path.join(app, 'test', 'widget_test.dart');
try {
  const contents = await fs.readFile(generatedTest, 'utf8');
  if (contents.includes('Counter increments smoke test') && contents.includes('const MyApp()')) {
    await fs.unlink(generatedTest);
  }
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}
for (const name of ['harmony_media.dart', 'harmony_support.dart']) {
  await fs.copyFile(path.join(root, 'harmony', 'adapter', name), path.join(app, 'lib', name));
}
await fs.copyFile(path.join(root, 'harmony', 'adapter', 'ocr_service.dart'),
  path.join(app, 'lib', 'services', 'ocr_service.dart'));
await fs.copyFile(path.join(root, 'harmony', 'smoke', 'native_smoke.dart'),
  path.join(app, 'lib', 'harmony_native_smoke.dart'));
const mainFile = path.join(app, 'lib', 'main.dart');
const main = await fs.readFile(mainFile, 'utf8');
await fs.writeFile(mainFile, `import 'harmony_support.dart';\n${main}`
  .replace('WidgetsFlutterBinding.ensureInitialized();',
    'WidgetsFlutterBinding.ensureInitialized();\n  await registerHarmonyPlatform();')
  .replace('publishableKey: _publishableKey,',
    'publishableKey: _publishableKey,\n      authOptions: FlutterAuthClientOptions(\n        localStorage: HarmonyAuthStorage(),\n        pkceAsyncStorage: HarmonyPkceStorage(),\n        detectSessionInUriPredicate: (uri) => uri.scheme == "collect" && uri.host == "auth" && uri.path == "/recovery",\n      ),'));
console.log('HarmonyOS business code prepared: ' + app);
