// Compile templates and styles with the published WeChat compiler wrapper.
// This is a local syntax check, not a substitute for Developer Tools or a phone.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const compilerPath = process.env.COLLECT_WECHAT_COMPILER_PATH ||
  path.join(root, '.tooling/wechat-compiler/node_modules/miniprogram-compiler');
const compiler = require(compilerPath);
for (const [name, compile] of [['WXML', compiler.wxmlToJs], ['WXSS', compiler.wxssToJs]]) {
  const result = compile(path.join(root, 'miniprogram'));
  if (typeof result !== 'string' || !result.length) throw new Error(`${name}: compiler output is empty`);
  new Function('global', result);
  console.log(`PASS: ${name}, ${Buffer.byteLength(result)} compiled bytes`);
}
const packageInfo = JSON.parse(fs.readFileSync(path.join(compilerPath, 'package.json'), 'utf8'));
console.log(`Compiler wrapper: ${packageInfo.name}@${packageInfo.version}`);
