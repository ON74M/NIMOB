
@echo off
REM ============================================================================
REM NIMOB_SYNC_INTELIGENTE.bat
REM
REM FINALIDADE:
REM   Executar a sincronizacao inteligente do NIMOB com duplo clique.
REM
REM ESTRUTURA OFICIAL:
REM   Matriz : D:\N74TEC\DOWNLOAD\GitHub
REM   Projeto: D:\N74TEC\DOWNLOAD\GitHub\ON74M\NIMOB
REM   Backup : D:\N74TEC\DOWNLOAD\GitHub\ON74M_BackUp\NIMOB
REM   GitHub : https://github.com/ON74M/NIMOB
REM
REM ARQUIVO COMPLEMENTAR:
REM   NIMOB_SYNC_INTELIGENTE.ps1
REM
REM MANUTENCAO:
REM   Manter os dois arquivos na pasta raiz do projeto.
REM   As configuracoes e regras ficam documentadas no PS1.
REM ============================================================================

setlocal EnableExtensions

title NIMOB - Sincronizacao Inteligente

REM Localiza o PowerShell na mesma pasta deste BAT.
set "SCRIPT=%~dp0NIMOB_SYNC_INTELIGENTE.ps1"

REM Verifica se o arquivo complementar existe.
if not exist "%SCRIPT%" (
    echo.
    echo ERRO: arquivo NIMOB_SYNC_INTELIGENTE.ps1 nao encontrado.
    echo.
    pause
    exit /b 2
)

REM Verifica se o PowerShell esta instalado.
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo ERRO: Windows PowerShell nao encontrado.
    pause
    exit /b 3
)

REM Executa o motor de sincronizacao.
REM A politica Bypass vale somente para esta execucao.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"

REM Guarda o codigo de retorno.
set "RESULT=%ERRORLEVEL%"

REM Apresenta o resultado.
echo.
if "%RESULT%"=="0" (
    echo ============================================================
    echo NIMOB: SINCRONIZACAO CONCLUIDA COM SUCESSO.
    echo ============================================================
) else (
    echo ============================================================
    echo NIMOB: PROCESSO INTERROMPIDO.
    echo Codigo de retorno: %RESULT%
    echo Consulte o relatorio e a mensagem de erro.
    echo ============================================================
)

echo.
pause
exit /b %RESULT%
