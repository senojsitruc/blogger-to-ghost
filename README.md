This is by no means a one-click solution. The code was initially written by AI. I fixed some bugs and got it running. You have to be able to build Swift command line apps to use this.

Download your blogger posts as JSON:

wget "https://senojsitruc.blogspot.com/feeds/posts/default?start-index=0&alt=json&max-results=10000"
wget "https://senojsitruc.blogspot.com/feeds/posts/default?start-index=150&alt=json&max-results=10000"
wget "https://senojsitruc.blogspot.com/feeds/posts/default?start-index=300&alt=json&max-results=10000"
wget "https://senojsitruc.blogspot.com/feeds/posts/default?start-index=450&alt=json&max-results=10000"

Use Google Takeout to download all of your media. Copy those into Ghost.

Build and run conversion:

swift build -c release
.build/release/blogger2ghost blogger.json > ghost.json

# Or compile in one step without SwiftPM:
swiftc -O main.swift -o blogger2ghost && ./blogger2ghost blogger.json > ghost.json

# Optional: specify an explicit output path
.build/release/blogger2ghost blogger.json -o ghost.json
