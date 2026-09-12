import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';

/**
 * 附件（轮 8 + 轮 13 压缩）：系统图片选择器 → 读文件 → base64 dataURL。
 * 压缩对齐 web（>1MB 自动压缩）：decode → 缩放到最长边 1280 → jpeg q80（SDK d.ts 已核对
 * createImageSource(buf) / createPixelMap({desiredSize}) / ImagePacker.packing({format, quality})）。
 * 小图保留原字节（mime 按 URI 扩展名判定）；上限 20MB。
 */
export class Attachments {
  /** 返回 data:<mime>;base64,...；取消或超限返回 '' */
  static async pickImage(): Promise<string> {
    const picker = new photoAccessHelper.PhotoViewPicker();
    const opt: photoAccessHelper.PhotoSelectOptions = {
      MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
      maxSelectNumber: 1
    };
    const result = await picker.select(opt);
    if (!result.photoUris || result.photoUris.length === 0) { return ''; }
    const uri = result.photoUris[0];
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const st = fs.statSync(file.fd);
    if (st.size > 20 * 1024 * 1024) {
      fs.closeSync(file);
      return '';
    }
    const buf = new ArrayBuffer(st.size);
    fs.readSync(file.fd, buf);
    fs.closeSync(file);
    const bytes = new Uint8Array(buf);
    const b64Helper = new util.Base64Helper();
    let mime = 'image/jpeg';
    if (uri.endsWith('.png')) { mime = 'image/png'; }
    else if (uri.endsWith('.webp')) { mime = 'image/webp'; }
    let b64: string;
    if (st.size > 1 * 1024 * 1024) {
      try {
        const src = image.createImageSource(buf);
        const pm = await src.createPixelMap({ desiredSize: { width: 1280, height: 1280 } });
        const packer = image.createImagePacker();
        const opt2: image.PackingOption = { format: 'image/jpeg', quality: 80 };
        const outBuf = await packer.packing(pm, opt2);
        b64 = b64Helper.encodeToStringSync(new Uint8Array(outBuf));
        mime = 'image/jpeg';
      } catch (e) {
        // 压缩失败回退原字节
        b64 = b64Helper.encodeToStringSync(bytes);
      }
    } else {
      b64 = b64Helper.encodeToStringSync(bytes);
    }
    return 'data:' + mime + ';base64,' + b64;
  }
}
