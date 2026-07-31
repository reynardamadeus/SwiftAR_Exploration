# Hijauin
## Description
A platform for volunteering program exploration and application!

## What to Install
Karena pake file .xcodeproj udah dipastikan bakalan conflict, kita bakalan pakai tools namanya xcodegen
### XCodeGen
How to install?
1. install homebrew by copy-pastying this line through terminal
``` 
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
2. install xcodegen
``` 
brew install xcodegen 
```
3. Clone this repository

4. navigate through your clone project's file address, use ls for navigation and cd to open folder
```
cd Documents
cd . (to go back to previous folder)
```
5. run xcodegen in the folder with project.yml file
```
xcodegen generate
```
6. Open the generated .xcodeproj

Note: this may seems to be overkill, but i WILL NOT handle a 1.30 AM conflict just because theres a new swift file AGAIN ToT
