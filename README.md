# bashdep

A minimalistic and straightforward **bash dependency manager**.

---

### Usage

#### bashdep::install

You can distinguish between regular dependencies and dev-dependencies when defining the URL.
Dev-dependencies ends with `@dev`

```bash
DEPENDENCIES=(
  "https://github.com/[...]/download/0.17.0/bashunit"
  "https://github.com/[...]/download/0.1/dumper.sh@dev"
)

bashdep::install "${DEPENDENCIES[@]}"
```

#### bashdep::setup

Alternately, you can configure the default values of bashdep using the setup function.

- `dir=string`: set the default destination directory. Default: `lib`
- `dev-dir=string`: set the development destination directory. Default: `lib/dev`
- `silent=bool`: if true, no progress text will be shown during installation. Default: `false`

```bash
bashdep::setup dir="lib" dev-dir="src/dev" silent=false
bashdep::install "${DEPENDENCIES[@]}"
```

### Demo

Usage example from
[Chemaclass/bash-skeleton](https://github.com/Chemaclass/bash-skeleton/blob/main/install-dependencies.sh)

```bash
#!/bin/bash
[ ! -f lib/bashdep ] && {
  mkdir -p lib
  curl -sLo lib/bashdep https://github.com/Chemaclass/bashdep/releases/download/0.1/bashdep
  chmod +x lib/bashdep
}

DEPENDENCIES=(
  "https://github.com/TypedDevs/bashunit/releases/download/0.17.0/bashunit"
  "https://github.com/Chemaclass/create-pr/releases/download/0.6/create-pr"
  "https://github.com/Chemaclass/bash-dumper/releases/download/0.1/dumper.sh@dev"
)

source lib/bashdep
bashdep::setup dir="lib" dev-dir="src/dev" silent=false
bashdep::install "${DEPENDENCIES[@]}"
```

#### Output

```bash
Downloading 'bashunit' to 'lib'...
> bashunit installed successfully in 'lib'
Downloading 'create-pr' to 'lib'...
> create-pr installed successfully in 'lib'
Downloading 'dumper.sh' to 'src/dev'...
> dumper.sh installed successfully in 'src/dev'
```
