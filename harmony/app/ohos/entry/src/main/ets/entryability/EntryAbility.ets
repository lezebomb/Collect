
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { AbilityConstant, Want } from '@kit.AbilityKit';
import { HarmonyNativeBridge } from '../platform/HarmonyNativeBridge';

export default class EntryAbility extends FlutterAbility {
  private bridge?: HarmonyNativeBridge;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.bridge = new HarmonyNativeBridge(this.context);
    this.bridge.acceptLink(want.uri);
    super.onCreate(want, launchParam);
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    this.bridge?.register(flutterEngine);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam);
    this.bridge?.acceptLink(want.uri);
  }

  cleanUpFlutterEngine(flutterEngine: FlutterEngine): void {
    this.bridge?.dispose();
    super.cleanUpFlutterEngine(flutterEngine);
  }
}
