@echo off
:: Compile Hunyuan3D-2.0 texgen CUDA rasterizer (+ C++ renderer) for this GPU (sm_120) with MSVC 14.44 + CUDA 12.9. Run once.
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set CUDA_HOME=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.9
set CUDA_PATH=%CUDA_HOME%
set PATH=%CUDA_HOME%\bin;%PATH%
set TORCH_CUDA_ARCH_LIST=12.0
set DISTUTILS_USE_SDK=1
set ROOT=%~dp0Hunyuan3D2_WinPortable
cd /d %ROOT%
python_standalone\python.exe -s -m pip install --no-build-isolation .\Hunyuan3D-2\hy3dgen\texgen\custom_rasterizer
echo RASTER_EXIT %errorlevel%
python_standalone\python.exe -s -m pip install --no-build-isolation .\Hunyuan3D-2\hy3dgen\texgen\differentiable_renderer
echo RENDERER_EXIT %errorlevel%
python_standalone\python.exe -s -c "import custom_rasterizer_kernel; print('custom_rasterizer_kernel import ok')"
endlocal
