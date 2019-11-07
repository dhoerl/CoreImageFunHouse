# CoreImageFunHouse
Update of Apple's Core Image Fun House (FunHouse)

Apple's "Core Image Fun House" hasn't been updated since 2014. Not only does it use the deprecated OpenGL (as of Catalina), but it doesn't even use ARC! The app still builds and runs using Xcode 9, but in Xcode 10 Apple made the NSOpenGLView use an OpenGL layer, and so it crashes or does nothing when built with Xcode 10 or newer.

The goals of this project are to:
- get the project to build and run on Xcode 11 / Catalina
- convert the Objective C code to ARC
- convert the instance variables to properties
- migrate from using OpenGL to Metal
- convert the source code into Swift

As a first step, the original commit of the source will use the exact files that Apple supplied in the 2014 zip file:
  https://developer.apple.com/library/archive/samplecode/FunHouse/Introduction/Intro.html
 
 NOTE: I finally got it to (somewhat) work in Catalina - with a significant amount of effort
