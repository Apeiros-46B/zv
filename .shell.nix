{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell rec {
	nativeBuildInputs = with pkgs; [
		zig
		zls
		shader-slang
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

		# for opengl
		mesa
		mesa-demos
		mesa-gl-headers
		libGL
		libGLU
		shaderc
	];

	shellHook = ''
		export LD_LIBRARY_PATH="/run/opengl-driver/lib:/run/opengl-driver-32/lib:${builtins.toString (pkgs.lib.makeLibraryPath buildInputs)}:$LD_LIBRARY_PATH"
	'';

	SHADERC_LIB_DIR = "${pkgs.shaderc.lib}/lib";
	DISPLAY = ":0";
}
