@echo off
@setlocal enabledelayedexpansion

:start
del *.exe *.obj *.pdb *.ilk >nul 2>&1
cl /EHsc /Bv hello.cpp %*
goto :done

:done
popd
