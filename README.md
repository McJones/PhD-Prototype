# PhD-Prototype

The Prototype I build REALLY quickly for my PhD.
The prototype works like a compass but instead of pointing north, it points to friends.
Technically it points to other people using the app, but eh that sounds dull.

All three versions of the prototype are included, each one a different commit because why not? I was busy, don't judge.

##Details
Ok so it uses CoreLocation to get a currentl location, this location is then sent out over the PubNub stream to every other device running the prototype.

When the app receives the location from the target it uses great circle mapping to determine the heading to point to that location, assuming the phone is facing north.

All the while it is using CoreLocation to determine the phones current heading, this is then subtracted from the target heading and viola, you've got a compass that points to friends.

##Huh?
**How do I build this?**

It is an iOS project, you need Xcode to build it.

**What does it run on?**

It should run on any iOS 7 or above device.

**Tim, did you leave PubNub credentials in there?!**

Yep, for a temporary account I made and have since forgotten the password for.

**You used PubNub incorrectly**

Probably, I was still learning how to use it at the time
