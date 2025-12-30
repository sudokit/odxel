default: run

build:
    odin build src -debug

run: build
    SDL_VIDEODRIVER=wayland ./src.bin

check_error:
    -@odin check src

rdoc:
    QT_QPA_PLATFORM=xcb qrenderdoc &
    
