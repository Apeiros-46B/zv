{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell rec {
	nativeBuildInputs = with pkgs; [
		zig
		zls
		shader-slang
		vulkan-validation-layers
	];

	buildInputs = with pkgs; [
		# for embedding lua
		luajit

		# for SDL2
		(SDL2.overrideAttrs (old: {
			postInstall = (old.postInstall or "") + ''
				ln -s libSDL2.so $out/lib/libsdl2.so
			'';
		}))

		# for wgpu
		libGL
		shaderc
		vulkan-headers
		vulkan-loader
		vulkan-tools
		vulkan-tools-lunarg
		vulkan-extension-layer
		vulkan-validation-layers
	];

	shellHook = ''
		export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${builtins.toString (pkgs.lib.makeLibraryPath buildInputs)}"
	'';

	SHADERC_LIB_DIR = "${pkgs.shaderc.lib}/lib";
}
