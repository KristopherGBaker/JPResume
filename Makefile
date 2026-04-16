.PHONY: build test lint fix clean project install bootstrap

build:
	swift build

test:
	swift test

lint:
	swiftlint lint

fix:
	swiftlint lint --fix

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
