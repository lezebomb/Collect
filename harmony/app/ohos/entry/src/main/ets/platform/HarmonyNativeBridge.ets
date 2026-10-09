import { common } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  Any, FlutterEngine, MethodCall, MethodChannel, MethodCallHandler, MethodResult,
  EventChannel, EventSink, StreamHandler
} from '@ohos/flutter_ohos';

/** Device APIs only. Collection data and backup format stay in shared Dart. */
export class HarmonyNativeBridge implements MethodCallHandler, StreamHandler {
  private context: common.UIAbilityContext;
  private channel?: MethodChannel;
  private events?: EventChannel;
  private sink?: EventSink;
  private firstLink?: string;
  private lastLink?: string;
  private picking: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  register(engine: FlutterEngine): void {
    const messenger = engine.getDartExecutor().getBinaryMessenger();
    this.channel = new MethodChannel(messenger, 'app.dearshelf/native');
    this.channel.setMethodCallHandler(this);
    this.events = new EventChannel(messenger, 'app.dearshelf/links');
    this.events.setStreamHandler(this);
  }

  dispose(): void {
    this.channel?.setMethodCallHandler(null);
    this.events?.setStreamHandler(null);
    this.sink = undefined;
  }

  acceptLink(uri?: string): void {
    if (!uri || !uri.startsWith('collect://auth/recovery')) return;
    if (!this.firstLink) this.firstLink = uri;
    this.lastLink = uri;
    this.sink?.success(uri);
  }

  onListen(_args: Any, sink: EventSink): void {
    this.sink = sink;
    if (this.lastLink) sink.success(this.lastLink);
  }

  onCancel(_args: Any): void {
    this.sink = undefined;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.dispatch(call, result).catch((error: BusinessError) => {
      result.error('HARMONY_NATIVE', error.message ?? '系统操作失败', null);
    });
  }

  private async dispatch(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'paths': {
        const paths = new Map<string, string>();
        paths.set('files', this.context.filesDir);
        paths.set('cache', this.context.cacheDir);
        result.success(paths);
        break;
      }
      case 'initialLink':
        result.success(this.firstLink ?? null);
        break;
      case 'latestLink':
        result.success(this.lastLink ?? null);
        break;
      case 'pickImage':
        result.success(await this.pickImage(call));
        break;
      case 'recoverImage':
        result.success(await this.recoverImage());
        break;
      case 'normalizeImage': {
        const path = call.argument('path') as string;
        this.assertPrivatePath(path);
        result.success(await this.normalizeImage(path,
          call.argument('maxWidth') as number, call.argument('maxHeight') as number,
          call.argument('quality') as number));
        break;
      }
      case 'consumeImage':
        this.clearPendingImage();
        result.success(null);
        break;
      case 'pickFiles':
        result.success(await this.pickFiles(call));
        break;
      case 'saveFile':
        result.success(await this.saveFile(call));
        break;
      case 'recognizeText':
        result.success(await this.recognizeText(call.argument('path') as string));
        break;
      default:
        result.notImplemented();
    }
  }

  private assertPrivatePath(path: string): void {
    if (path.includes('/../') ||
      (!path.startsWith(this.context.cacheDir + '/') &&
      !path.startsWith(this.context.filesDir + '/'))) {
      throw new Error('无效的应用文件路径');
    }
  }

  private pendingFile(): string {
    return this.context.filesDir + '/pending-image.txt';
  }

  private setPendingImage(path: string): void {
    this.assertPrivatePath(path);
    const file = fileIo.openSync(this.pendingFile(),
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, path);
      fileIo.fsyncSync(file.fd);
    } finally {
      fileIo.closeSync(file);
    }
  }

  private clearPendingImage(): void {
    if (fileIo.accessSync(this.pendingFile())) fileIo.unlinkSync(this.pendingFile());
  }

  private async recoverImage(): Promise<string | null> {
    if (!fileIo.accessSync(this.pendingFile())) return null;
    const path = fileIo.readTextSync(this.pendingFile());
    this.assertPrivatePath(path);
    if (!fileIo.accessSync(path) || fileIo.statSync(path).size === 0) {
      this.clearPendingImage();
      return null;
    }
    if (path.startsWith(this.context.cacheDir + '/image-')) return path;
    const recovered = await this.normalizeImage(path, 2000, 2000, 85);
    this.setPendingImage(recovered);
    fileIo.unlinkSync(path);
    return recovered;
  }

  private async pickImage(call: MethodCall): Promise<string | null> {
    if (this.picking) throw new Error('图片选择已在进行，请稍候');
    this.picking = true;
    let rawCameraPath: string | undefined;
    try {
      let uri: string | undefined;
      if ((call.argument('source') as string) === 'camera') {
        rawCameraPath = this.context.cacheDir + '/camera-' + Date.now() + '.jpg';
        const file = fileIo.openSync(rawCameraPath,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
        fileIo.closeSync(file);
        this.setPendingImage(rawCameraPath);
        const profile: cameraPicker.PickerProfile = {
          cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
          saveUri: fileUri.getUriFromPath(rawCameraPath)
        };
        const captured = await cameraPicker.pick(this.context,
          [cameraPicker.PickerMediaType.PHOTO], profile);
        if (captured.resultCode !== 0) {
          this.clearPendingImage();
          return null;
        }
        uri = captured.resultUri;
      } else {
        const options = new photoAccessHelper.PhotoSelectOptions();
        options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
        options.maxSelectNumber = 1;
        const selected = await new photoAccessHelper.PhotoViewPicker().select(options);
        uri = selected.photoUris[0];
      }
      if (!uri) return null;
      const path = await this.normalizeImage(uri,
        call.argument('maxWidth') as number, call.argument('maxHeight') as number,
        call.argument('quality') as number);
      this.setPendingImage(path);
      return path;
    } finally {
      this.picking = false;
      if (rawCameraPath && fileIo.accessSync(rawCameraPath)) {
        // Keep raw camera data until a successful normalized file exists.
        const marker = fileIo.accessSync(this.pendingFile())
          ? fileIo.readTextSync(this.pendingFile()) : '';
        if (marker !== rawCameraPath) fileIo.unlinkSync(rawCameraPath);
      }
    }
  }

  private async normalizeImage(uri: string, maxWidth: number,
    maxHeight: number, quality: number): Promise<string> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    let source: image.ImageSource | undefined;
    let pixelMap: image.PixelMap | undefined;
    let packer: image.ImagePacker | undefined;
    let output: fileIo.File | undefined;
    try {
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      const orientation = await this.readOrientation(source);
      const swapped = orientation >= 5;
      const visualWidth = swapped ? info.size.height : info.size.width;
      const visualHeight = swapped ? info.size.width : info.size.height;
      const scale = Math.min(1, Math.max(1, maxWidth) / visualWidth,
        Math.max(1, maxHeight) / visualHeight);
      const decoding: image.DecodingOptions = {
        desiredSize: {
          width: Math.max(1, Math.round(info.size.width * scale)),
          height: Math.max(1, Math.round(info.size.height * scale))
        },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: true
      };
      pixelMap = await source.createPixelMap(decoding);
      if (orientation === 2 || orientation === 5 || orientation === 7) {
        await pixelMap.flip(true, false);
      } else if (orientation === 4) {
        await pixelMap.flip(false, true);
      }
      if (orientation === 3) await pixelMap.rotate(180);
      if (orientation === 6 || orientation === 7) await pixelMap.rotate(90);
      if (orientation === 5 || orientation === 8) await pixelMap.rotate(270);
      const pixelInfo = await pixelMap.getImageInfo();
      const preserveAlpha = info.mimeType === 'image/png' || info.mimeType === 'image/webp' ||
        (pixelInfo.alphaType !== image.AlphaType.OPAQUE &&
        pixelInfo.alphaType !== image.AlphaType.UNKNOWN);
      const destination = this.context.cacheDir + '/image-' + Date.now() +
        (preserveAlpha ? '.png' : '.jpg');
      packer = image.createImagePacker();
      output = await fileIo.open(destination,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await packer.packToFile(pixelMap, output.fd, {
        format: preserveAlpha ? 'image/png' : 'image/jpeg',
        quality: Math.min(100, Math.max(1, quality))
      });
      return destination;
    } finally {
      if (output) await fileIo.close(output);
      if (packer) await packer.release();
      if (pixelMap) await pixelMap.release();
      if (source) await source.release();
      await fileIo.close(file);
    }
  }

  private async readOrientation(source: image.ImageSource): Promise<number> {
    try {
      const value = await source.getImageProperty(image.PropertyKey.ORIENTATION);
      switch (value.toLowerCase()) {
        case '2': case 'top-right': return 2;
        case '3': case 'bottom-right': return 3;
        case '4': case 'bottom-left': return 4;
        case '5': case 'left-top': return 5;
        case '6': case 'right-top': return 6;
        case '7': case 'right-bottom': return 7;
        case '8': case 'left-bottom': return 8;
        default: return 1;
      }
    } catch (_) {
      // Images without EXIF orientation already use their stored direction.
      return 1;
    }
  }

  private async pickFiles(call: MethodCall): Promise<string[]> {
    const extensions = (call.argument('extensions') as string[]) ?? [];
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = call.argument('single') === true ? 1 : 100;
    if (extensions.length > 0) {
      options.fileSuffixFilters = ['收藏文件|' + extensions.map(
        (extension: string) => '.' + extension).join(',')];
    }
    const uris = await new picker.DocumentViewPicker(this.context).select(options);
    const paths: string[] = [];
    for (let index = 0; index < uris.length; index++) {
      const input = await fileIo.open(uris[index], fileIo.OpenMode.READ_ONLY);
      try {
        const folder = this.context.cacheDir + '/import-' + Date.now() + '-' + index;
        fileIo.mkdirSync(folder);
        const name = new fileUri.FileUri(uris[index]).name.replace(/[\\/]/g, '_');
        const destination = folder + '/' +
          (!name || name === '.' || name === '..' ? 'backup' : name);
        if ((await fileIo.stat(input.fd)).size > 512 * 1024 * 1024) {
          throw new Error('单个文件不能超过 512 MB');
        }
        await fileIo.copyFile(input.fd, destination);
        paths.push(destination);
      } finally {
        await fileIo.close(input);
      }
    }
    return paths;
  }

  private async saveFile(call: MethodCall): Promise<string | null> {
    const path = call.argument('path') as string;
    this.assertPrivatePath(path);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [call.argument('fileName') as string];
    const uris = await new picker.DocumentViewPicker(this.context).save(options);
    if (uris.length === 0) return null;
    const output = await fileIo.open(uris[0],
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.copyFile(path, output.fd);
      await fileIo.fsync(output.fd);
    } finally {
      await fileIo.close(output);
    }
    return uris[0];
  }

  private async recognizeText(path: string): Promise<string[]> {
    this.assertPrivatePath(path);
    if (!canIUse('SystemCapability.AI.OCR.TextRecognition')) {
      throw new Error('当前系统未提供文字识别服务，请手动填写信息');
    }
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    let source: image.ImageSource | undefined;
    let pixelMap: image.PixelMap | undefined;
    let initialized = false;
    try {
      source = image.createImageSource(file.fd);
      pixelMap = await source.createPixelMap({
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      try {
        initialized = await textRecognition.init();
      } catch (error) {
        const nativeError = error as BusinessError;
        if (typeof nativeError.code !== 'number') {
          throw new Error('当前系统未提供文字识别服务，请手动填写信息');
        }
        throw new Error(nativeError.message);
      }
      if (!initialized) throw new Error('系统文字识别初始化失败');
      const vision: textRecognition.VisionInfo = { pixelMap: pixelMap };
      const recognized = await textRecognition.recognizeText(vision);
      const lines: string[] = [];
      recognized.blocks.forEach((block: textRecognition.TextBlock) => {
        block.lines.forEach((line: textRecognition.TextLine) => lines.push(line.value));
      });
      return lines;
    } finally {
      if (initialized) await textRecognition.release();
      if (pixelMap) await pixelMap.release();
      if (source) await source.release();
      await fileIo.close(file);
    }
  }
}
