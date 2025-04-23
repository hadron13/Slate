curl -L https://github.com/odin-lang/Odin/releases/download/dev-2025-04/odin-windows-amd64-dev-2025-04.zip --ssl-no-revoke > odin.zip
mkdir odin 
powershell -command "Expand-Archive -Path 'odin.zip' -DestinationPath '.\odin'"
del odin.zip
