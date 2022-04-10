// BLOGGIE UNWARPING EXPORTER 
// For panoramic video from the Sony Bloggie (MHS-PM5K)
// By Golan Levin, 2010 - 2022 • http://www.flong.com
// For Processing 4.0b7+; Only tested on OSX 12.3.1

// INSTRUCTIONS:
// 1. Install Processing from https://processing.org/
// 2. Launch Processing; install the "Video Library for Processing 4"
//    by going Sketch -> Import Library -> Add Library...
// 3. Make sure your Bloggie video opens in Quicktime.
//    Put your Bloggie video in the "data" folder of this sketch.
// 4. Edit the "settings.txt" file so that INPUT_WIDTH, INPUT_HEIGHT,
//    and INPUT_FRAME_RATE match the properties of your Bloggie video.
// 5. Click Play (Command-R) to run this sketch; your video should play.
// 6. Adjust the horizontal position of the video with the mouseX. 
// 7. Use the arrow keys to adjust the center point of the annulus. 
//    This will get rid of any "sine wave" warping across the panorama.
// 8. Press the 'e' key to begin exporting JPG frames from the video. 
//    These will appear in a new "output" folder (in this sketch folder).
//    Keep an eye on the export progress in the Processing console. 
// 9. Use your favorite video software to reassemble the video frames
//    into a video. Sorry there's no video export here!

import processing.video.*;
//=============================================
// Important parameters for the unwarping
float imgCx; // optical x-center of the warped (annular) image
float imgCy; // optical y-center of the warped (annular) image
float maxR;  // outer radius of the warped annulus, in pixels
float minR;  // inner radius of the warped annulus, in pixels

//=============================================
// The input (warped, annular, donut) image
String inputMovieFilename;
Movie inputMovie;
int   inputImageW;
int   inputImageH;
float inputMovieFrameRate;

// The output (unwarped, panoramic) image
PImage outputImage;
int    unwarpedW;
int    unwarpedH;
float  unwarpedAspectRatio;
int    outgoingFrameCount;
boolean bExporting;
boolean bGeometryChanged;

// Intermediate data structures for the unwarping
float angularShift;
float srcxArray[];
float srcyArray[];
int   patchR[][];
int   patchG[][];
int   patchB[][];

// Don't touch these parameters,
// they are specific to the nonlinearities of the Bloggie lens.
float yWarpA =   0.1850;
float yWarpB =   0.8184;
float yWarpC =  -0.0028;

//=============================================
void settings() {

  /*
   // Example settings file:
   
   INPUT_FILENAME, input.mp4
   INPUT_WIDTH, 340
   INPUT_HEIGHT, 288
   INPUT_FRAME_RATE, 29.97
   OPTICAL_CENTER_X, 0.52647
   OPTICAL_CENTER_Y, 0.51042
   MAX_R_PERCENT, 0.97
   MIN_R_PERCENT, 0.22
   ANGLE_SHIFT, 265.0
   OUTPUT_WIDTH, 720
   
   */

  // Default values; these are overwritten by settings.txt
  inputMovieFilename = "input.mp4";
  inputImageW = 340;
  inputImageH = 288;
  inputMovieFrameRate = 29.97;
  maxR  = inputImageH/2.0 * 0.97;
  minR  = inputImageH/2.0 * 0.22;
  imgCx = inputImageW/2;
  imgCy = inputImageH/2;
  angularShift = 265.0;
  unwarpedW = 720;

  // Load settings file, clobbering above values as necessary.
  String paramFileLines[] = loadStrings("settings.txt");
  if (paramFileLines.length > 0) {
    for (int i=0; i<paramFileLines.length; i++) {
      String lineStrings[] = splitTokens(paramFileLines[i], ", \t");
      if (lineStrings.length == 2) {
        if (lineStrings[0].equals("INPUT_FILENAME")) {
          inputMovieFilename = lineStrings[1];
        } else if  (lineStrings[0].equals("INPUT_WIDTH")) {
          inputImageW = Integer.valueOf(lineStrings[1]);
        } else if  (lineStrings[0].equals("INPUT_HEIGHT")) {
          inputImageH = Integer.valueOf(lineStrings[1]);
        } else if  (lineStrings[0].equals("INPUT_FRAME_RATE")) {
          inputMovieFrameRate = Float.valueOf(lineStrings[1]);
        } else if  (lineStrings[0].equals("OPTICAL_CENTER_X")) {
          imgCx = inputImageW * Float.valueOf(lineStrings[1]);
        } else if  (lineStrings[0].equals("OPTICAL_CENTER_Y")) {
          imgCy = inputImageH * Float.valueOf(lineStrings[1]);
        } else if  (lineStrings[0].equals("MAX_R_PERCENT")) {
          maxR = (inputImageH/2.0) * Float.valueOf(lineStrings[1]);
        } else if  (lineStrings[0].equals("MIN_R_PERCENT")) {
          minR = (inputImageH/2.0) * Float.valueOf(lineStrings[1]);
        } else if  (lineStrings[0].equals("ANGLE_SHIFT")) {
          angularShift = DEG_TO_RAD * Float.valueOf(lineStrings[1]);
        } else if  (lineStrings[0].equals("OUTPUT_WIDTH")) {
          unwarpedW = Integer.valueOf(lineStrings[1]);
        }
      }
    }
  }

  // The Bloggie has an approximately 60-degree vertical field of view.
  float bloggieVerticalFOV = 60.0;
  unwarpedAspectRatio = 360.0/bloggieVerticalFOV;
  unwarpedH = (int)(unwarpedW / unwarpedAspectRatio);
  outputImage = createImage(unwarpedW, unwarpedH, RGB);
  size(unwarpedW, unwarpedH);

  srcxArray = new float[unwarpedW*unwarpedH];
  srcyArray = new float[unwarpedW*unwarpedH];
  patchR = new int[4][4];
  patchG = new int[4][4];
  patchB = new int[4][4];

  bExporting = false;
  bGeometryChanged = true;
  outgoingFrameCount = 0;
  computeInversePolarTransform();
}

//=============================================
void setup() {
  inputMovie = new Movie(this, inputMovieFilename);
  inputMovie.loop();
  inputMovie.read();
  delay(10);
}

//=============================================
void draw() {
  image(outputImage, 0, 0);
}

//=============================================
void movieEvent (Movie inputMovie) {
  if (inputMovie.available()) {
    inputMovie.read();
    computeInversePolarTransform();
    unwarpBicubic(); // or unwarpNearestNeighbor();

    if (bExporting) {
      float currPlaybackTime = inputMovie.time();
      int nFramesToExport = (int)(inputMovie.duration() * inputMovieFrameRate);
      outgoingFrameCount++;
      println("Exporting frame #" + outgoingFrameCount + "/"
        + nFramesToExport + " (" + currPlaybackTime  + "s)");
        
      saveFrame("output/output_frame_" + nf(outgoingFrameCount, 5) + ".jpg");
      
      if (outgoingFrameCount >= nFramesToExport) {
        bExporting = false;
        println("Finished exporting frames.");
      }
    }
  }
}

//=============================================
void keyPressed() {
  switch (key) {

  case 'e':
  case 'E':
    // EXPORT the unwarped output frames.
    if (bExporting == false) {
      inputMovie.jump(0.0);
      inputMovie.play();
      inputMovie.jump(0.0);
      outgoingFrameCount = 0;
      bExporting = true;
    }
    break;

  case 'x':
    // Stop the video export prematurely
    if (bExporting == true) {
      bExporting = false;
      println("Aborting frame export.");
    }
    break;
  }

  // OR, Nudge the center point for unwarping the input image.
  float incr = 0.25;
  if ((keyCode >= 37) && (keyCode <= 40)) {
    switch (keyCode) {
    case 37: // LEFT
      imgCx  -= incr;
      break;
    case 39: // RIGHT
      imgCx  += incr;
      break;
    case 40: // DOWN
      imgCy  += incr;
      break;
    case 38: // UP
      imgCy  -= incr;
      break;
    }
    bGeometryChanged = true;
    println ("Input image center: (" + imgCx + ", " + imgCy + ")");
  }
}

//=============================================
void mouseDragged() {
  angularShift = map (mouseX, 0, width, 0, TWO_PI);
  bGeometryChanged = true;
  println (degrees(angularShift)); 
}

//=============================================
void computeInversePolarTransform() {
  if (bGeometryChanged) {
    int   dstRow, dstIndex;
    float radius, angle;

    for (int dsty=0; dsty<unwarpedH; dsty++) {
      float y = ((float)dsty/ (float)unwarpedH); //0..1
      float yfrac = yWarpA*y*y + yWarpB*y + yWarpC;
      radius  = (yfrac * (maxR-minR)) + minR;
      dstRow = dsty*unwarpedW;

      for (int dstx=0; dstx<unwarpedW; dstx++) {
        dstIndex = dstRow + dstx;
        angle    = (0 - ((float)dstx/(float)unwarpedW) * TWO_PI) + angularShift;
        srcxArray[dstIndex] = imgCx + radius*cos(angle);
        srcyArray[dstIndex] = imgCy + radius*sin(angle);
      }
    }
    bGeometryChanged = false;
  }
}

//=============================================
void unwarpNearestNeighbor() {

  int inputImageN = inputImageW * inputImageH;
  int dstRow, dstIndex;
  int srcx, srcy, srcIndex;
  color black = color(0, 0, 0);

  outputImage.loadPixels();
  color inputMoviePixels[]  = inputMovie.pixels;
  color outputImagePixels[] = outputImage.pixels;

  for (int dsty=0; dsty<unwarpedH; dsty++) {
    dstRow = dsty*unwarpedW;

    for (int dstx=0; dstx<unwarpedW; dstx++) {
      dstIndex = dstRow + dstx;
      srcx  = (int) srcxArray[dstIndex];
      srcy  = (int) srcyArray[dstIndex];
      srcIndex = srcy*inputImageW + srcx;

      if ((srcIndex >= 0) && (srcIndex < inputImageN)) {
        outputImagePixels[dstIndex] = inputMoviePixels[srcIndex];
      } else {
        outputImagePixels[dstIndex] = black;
      }
    }
  }
  outputImage.updatePixels();
}

//=============================================
void unwarpBicubic() {
  int dstRow, dstIndex;
  float srcxf, srcyf;
  float px, py;
  float px2, py2;
  float px3, py3;

  float interpR, interpG, interpB;
  int srcx, srcy, srcIndex;
  color black = color(0, 0, 0);
  color srcColor;
  color col;
  int patchIndex;
  int loIndex = inputImageW+1;
  int hiIndex = (inputImageW*inputImageH)-(inputImageW*3)-1;
  int patchRow;
  color inputPixels[] = inputMovie.pixels;
  color outputImagePixels[] = outputImage.pixels;

  outputImage.loadPixels();
  for (int dsty=0; dsty<unwarpedH; dsty++) {
    dstRow = dsty*width;

    for (int dstx=0; dstx<unwarpedW; dstx++) {
      dstIndex = dstRow + dstx;
      srcxf = srcxArray[dstIndex];
      srcyf = srcyArray[dstIndex];
      srcx  = (int) srcxf;
      srcy  = (int) srcyf;
      srcIndex = srcy*inputImageW + srcx;
      srcColor = black;

      for (int dy=0; dy<4; dy++) {
        patchRow = srcIndex + ((dy-1)*inputImageW);
        for (int dx=0; dx<4; dx++) {
          patchIndex = patchRow + (dx-1);
          if ((patchIndex >= loIndex) && (patchIndex < hiIndex)) {
            srcColor = inputPixels[patchIndex];
          }
          patchR[dx][dy] = (srcColor & 0x00FF0000) >> 16;
          patchG[dx][dy] = (srcColor & 0x0000FF00) >>  8;
          patchB[dx][dy] = (srcColor & 0x000000FF)      ;
        }
      }

      px = srcxf - srcx;
      py = srcyf - srcy;
      px2 =  px * px;
      px3 = px2 * px;
      py2 =  py * py;
      py3 = py2 * py;

      interpR = bicubicInterpolate (patchR, px, py, px2, py2, px3, py3);
      interpG = bicubicInterpolate (patchG, px, py, px2, py2, px3, py3);
      interpB = bicubicInterpolate (patchB, px, py, px2, py2, px3, py3);

      col = color (interpR, interpG, interpB);
      outputImagePixels[dstIndex] = col;
    }
  }
  outputImage.updatePixels();
}

//=============================================
float bicubicInterpolate (int[][] p, float x, float y, float x2, float y2, float x3, float y3) {
  // adapted from http://www.paulinternet.nl/?page=bicubic.
  // Note that this code can produce values outside of 0...255, due to cubic overshoot.
  // Processing prvents that from happening, but C++ doesn't. Clamp the output if this happens.

  int p00 = p[0][0];
  int p10 = p[1][0];
  int p20 = p[2][0];
  int p30 = p[3][0];

  int p01 = p[0][1];
  int p11 = p[1][1];
  int p21 = p[2][1];
  int p31 = p[3][1];

  int p02 = p[0][2];
  int p12 = p[1][2];
  int p22 = p[2][2];
  int p32 = p[3][2];

  int p03 = p[0][3];
  int p13 = p[1][3];
  int p23 = p[2][3];
  int p33 = p[3][3];

  int a00 =    p11;
  int a01 =   -p10 +   p12;
  int a02 =  2*p10 - 2*p11 +   p12 -   p13;
  int a03 =   -p10 +   p11 -   p12 +   p13;
  int a10 =   -p01 +   p21;
  int a11 =    p00 -   p02 -   p20 +   p22;
  int a12 = -2*p00 + 2*p01 -   p02 +   p03 + 2*p20 - 2*p21 +   p22 -   p23;
  int a13 =    p00 -   p01 +   p02 -   p03 -   p20 +   p21 -   p22 +   p23;
  int a20 =  2*p01 - 2*p11 +   p21 -   p31;
  int a21 = -2*p00 + 2*p02 + 2*p10 - 2*p12 -   p20 +   p22 +   p30 -   p32;
  int a22 =  4*p00 - 4*p01 + 2*p02 - 2*p03 - 4*p10 + 4*p11 - 2*p12 + 2*p13 + 2*p20 - 2*p21 + p22 - p23 - 2*p30 + 2*p31 - p32 + p33;
  int a23 = -2*p00 + 2*p01 - 2*p02 + 2*p03 + 2*p10 - 2*p11 + 2*p12 - 2*p13 -   p20 +   p21 - p22 + p23 +   p30 -   p31 + p32 - p33;
  int a30 =   -p01 +   p11 -   p21 +   p31;
  int a31 =    p00 -   p02 -   p10 +   p12 +   p20 -   p22 -   p30 +   p32;
  int a32 = -2*p00 + 2*p01 -   p02 +   p03 + 2*p10 - 2*p11 +   p12 -   p13 - 2*p20 + 2*p21 - p22 + p23 + 2*p30 - 2*p31 + p32 - p33;
  int a33 =    p00 -   p01 +   p02 -   p03 -   p10 +   p11 -   p12 +   p13 +   p20 -   p21 + p22 - p23 -   p30 +   p31 - p32 + p33;

  return
    a00      + a01 * y      + a02 * y2      + a03 * y3 +
    a10 * x  + a11 * x  * y + a12 * x  * y2 + a13 * x  * y3 +
    a20 * x2 + a21 * x2 * y + a22 * x2 * y2 + a23 * x2 * y3 +
    a30 * x3 + a31 * x3 * y + a32 * x3 * y2 + a33 * x3 * y3;
}
