.PHONY: build test lint fix clean project install bootstrap bump-patch bump-minor bump-major

build:
	swift build

test:
	swift test

lint:
	mint run swiftlint lint

fix:
	mint run swiftlint lint --fix

clean:
	swift package clean
	rm -rf .build DerivedData

project:
	xcodegen generate

install:
	swift build -c release
	cp .build/release/jpresume /usr/local/bin/jpresume

bootstrap:
	mint bootstrap

bump-patch:
	python3 Scripts/bump_version.py --part patch

bump-minor:
	python3 Scripts/bump_version.py --part minor

bump-major:
	python3 Scripts/bump_version.py --part major
