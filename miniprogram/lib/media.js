function chooseImage() {
  return new Promise((resolve,reject)=>wx.chooseMedia({count:1,mediaType:['image'],sourceType:['album','camera'],sizeType:['compressed'],
    success:result=>resolve(result.tempFiles[0].tempFilePath),fail:error=>error.errMsg.includes('cancel')?resolve(null):reject(new Error('无法选择图片，请检查相册/相机权限'))}));
}
async function compact(filePath) {
  const info=await new Promise((resolve,reject)=>wx.getImageInfo({src:filePath,success:resolve,fail:()=>reject(new Error('无法读取图片'))}));
  const scale=Math.min(1,1600/Math.max(info.width,info.height));
  try {
    return await new Promise((resolve,reject)=>wx.compressImage({src:filePath,quality:82,
      compressedWidth:Math.max(1,Math.round(info.width*scale)),compressedHeight:Math.max(1,Math.round(info.height*scale)),
      success:r=>resolve(r.tempFilePath),fail:reject}));
  } catch (_) { return filePath; }
}
module.exports={chooseImage,compact};
