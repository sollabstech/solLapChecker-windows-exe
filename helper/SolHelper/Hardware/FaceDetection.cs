using Windows.Graphics.Imaging;
using Windows.Media.FaceAnalysis;
using Windows.Storage;
using Windows.Storage.Streams;

namespace SolHelper.Hardware;

/// <summary>
/// Counts faces in a still image with the face detector built into Windows
/// (Windows.Media.FaceAnalysis): offline, no model files to ship.
/// </summary>
static class FaceDetection
{
    /// <summary>Images are scaled down to this width first: detection stays fast and is just as reliable.</summary>
    const double MaxWidth = 640;

    public static async Task<(int Faces, int Width, int Height)> Detect(string path)
    {
        if (!FaceDetector.IsSupported)
            throw new NotSupportedException("Windows face detection is not available on this PC.");

        var file = await StorageFile.GetFileFromPathAsync(Path.GetFullPath(path));
        using IRandomAccessStream stream = await file.OpenAsync(FileAccessMode.Read);
        var decoder = await BitmapDecoder.CreateAsync(stream);

        var scale = Math.Min(1.0, MaxWidth / Math.Max(1u, decoder.OrientedPixelWidth));
        var transform = new BitmapTransform
        {
            ScaledWidth = (uint)Math.Max(1, Math.Round(decoder.PixelWidth * scale)),
            ScaledHeight = (uint)Math.Max(1, Math.Round(decoder.PixelHeight * scale)),
        };
        using var colour = await decoder.GetSoftwareBitmapAsync(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Premultiplied,
            transform,
            ExifOrientationMode.RespectExifOrientation,
            ColorManagementMode.DoNotColorManage);
        // The detector accepts Gray8 (and Nv12) bitmaps only, and decoders cannot produce Gray8 directly.
        using var bitmap = SoftwareBitmap.Convert(colour, BitmapPixelFormat.Gray8);

        var detector = await FaceDetector.CreateAsync();
        var faces = await detector.DetectFacesAsync(bitmap);
        return (faces.Count, bitmap.PixelWidth, bitmap.PixelHeight);
    }
}
