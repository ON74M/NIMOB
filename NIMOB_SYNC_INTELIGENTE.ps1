
#requires -Version 5.1
<#
===============================================================================
NIMOB_SYNC_INTELIGENTE.ps1
===============================================================================

OBJETIVO
  Sincronizacao bidirecional entre computador e GitHub.

ESTRUTURA OFICIAL
  Matriz:
    D:\N74TEC\DOWNLOAD\GitHub

  Projeto:
    D:\N74TEC\DOWNLOAD\GitHub\ON74M\NIMOB

  Backup:
    D:\N74TEC\DOWNLOAD\GitHub\ON74M_BackUp\NIMOB

  Repositorio:
    https://github.com/ON74M/NIMOB.git

REGRAS
  1. Arquivos iguais: nenhuma alteracao.
  2. Arquivos novos locais: enviados ao GitHub.
  3. Arquivos novos remotos: baixados para o computador.
  4. Alteracao somente local: prevalece local.
  5. Alteracao somente remota: prevalece GitHub.
  6. Alteracao nos dois lados: compara datas.
  7. Empate: preserva copia local adicional.
  8. Exclusoes: nao sao replicadas automaticamente.

BACKUP
  Cria uma copia integral antes das alteracoes.
  Nunca apaga backups anteriores.

IMPORTANTE SOBRE DATAS
  A data do ultimo commit remoto e uma aproximacao da data
  de edicao. Nao representa necessariamente a edicao original.

MANUTENCAO
  Atualizar esta documentacao sempre que as regras mudarem.
  Testar alteracoes antes de utilizar em producao.
===============================================================================
#>

$ErrorActionPreference = "Stop"

# ============================================================================
# 1. CONFIGURACAO CENTRAL
# Alterar caminhos e repositorio somente neste bloco.
# ============================================================================

$MatrixRoot = "D:\N74TEC\DOWNLOAD\GitHub"

$Project = Join-Path $MatrixRoot "ON74M\NIMOB"

$BackupRoot = Join-Path $MatrixRoot "ON74M_BackUp\NIMOB"

$Remote = "https://github.com/ON74M/NIMOB.git"

$Branch = "main"

# Identificadores exclusivos de cada execucao.
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"

$BackupDir = Join-Path $BackupRoot ("NIMOB_" + $Stamp)

$Report = Join-Path $BackupRoot ("NIMOB_SYNC_" + $Stamp + ".txt")

$TempRoot = Join-Path $env:TEMP ("NIMOB_REMOTE_" + [guid]::NewGuid().ToString("N"))


# ============================================================================
# 2. FUNCOES AUXILIARES
# ============================================================================

# Exibe mensagens e registra tudo no relatorio.
function Write-Log([string]$Message) {

    Write-Host $Message

    Add-Content -LiteralPath $Report -Value $Message -Encoding UTF8
}


# Executa comandos Git e verifica erros.
function Invoke-Git([string[]]$GitArgs) {

    & git -C $Project @GitArgs

    if ($LASTEXITCODE -ne 0) {

        throw "Falha no Git: git $($GitArgs -join ' ')"
    }
}


# Executa Git e retorna o resultado como texto.
function Get-GitText([string[]]$GitArgs) {

    $result = & git -C $Project @GitArgs 2>$null

    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return (($result | Out-String).Trim())
}


# Cria indice de arquivos recursivo.
# Ignora os arquivos internos do Git.
function Get-FileMap([string]$Root) {

    $map = @{}

    if (Test-Path -LiteralPath $Root) {

        Get-ChildItem -LiteralPath $Root -File -Recurse -Force |

            Where-Object {
                $_.FullName -notmatch '[\\/]\.git([\\/]|$)'
            } |

            ForEach-Object {

                $relative = $_.FullName.Substring(
                    $Root.TrimEnd('\').Length
                ).TrimStart('\')

                $map[$relative] = $_.FullName
            }
    }

    return $map
}


# ============================================================================
# 3. ROTINA PRINCIPAL
# ============================================================================

try {

    # Criar diretorio de backup.
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

    # Iniciar relatorio.
    Set-Content -LiteralPath $Report `
        -Value "NIMOB - RELATORIO DE SINCRONIZACAO $Stamp" `
        -Encoding UTF8

    Write-Log "============================================================"
    Write-Log "NIMOB - SINCRONIZACAO INTELIGENTE"
    Write-Log "Matriz : $MatrixRoot"
    Write-Log "Projeto: $Project"
    Write-Log "Remoto : $Remote"
    Write-Log "Branch : $Branch"
    Write-Log "============================================================"


    # ========================================================================
    # 4. VALIDACAO
    # ========================================================================

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {

        throw "Git nao encontrado."
    }

    if (-not (Test-Path -LiteralPath $Project -PathType Container)) {

        throw "Pasta do projeto nao encontrada: $Project"
    }

    if (-not (Test-Path -LiteralPath (Join-Path $Project ".git"))) {

        throw "Esta pasta nao e um repositorio Git."
    }

    $origin = Get-GitText @("remote", "get-url", "origin")

    if (-not $origin) {

        throw "Remoto origin nao configurado."
    }

    $normalizedOrigin = $origin.TrimEnd('/')
    $normalizedExpected = $Remote.TrimEnd('/')

    if (
        $normalizedOrigin -ne $normalizedExpected -and
        $normalizedOrigin -ne $Remote.TrimEnd('.git').TrimEnd('/')
    ) {

        throw "Remoto incorreto: $origin"
    }

    $currentBranch = Get-GitText @("branch", "--show-current")

    if ($currentBranch -ne $Branch) {

        throw "Branch incorreta. Esperado: $Branch"
    }


    # ========================================================================
    # 5. BACKUP INTEGRAL
    # ========================================================================

    Write-Log ""
    Write-Log "[1/6] Criando backup integral..."

    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

    # Copia todos os arquivos e pastas, exceto .git.
    & robocopy $Project $BackupDir /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 `
        /XD (Join-Path $Project ".git") /NFL /NDL /NJH /NJS | Out-Null

    if ($LASTEXITCODE -ge 8) {

        throw "Erro na criacao do backup. Codigo: $LASTEXITCODE"
    }

    Write-Log "Backup criado: $BackupDir"


    # ========================================================================
    # 6. CONSULTA AO GITHUB
    # ========================================================================

    Write-Log ""
    Write-Log "[2/6] Consultando GitHub..."

    Invoke-Git @("fetch", "origin")

    $remoteBranch = Get-GitText @(
        "rev-parse", "--verify", "origin/$Branch"
    )

    if (-not $remoteBranch) {

        throw "Branch remota nao encontrada."
    }

    # Protege commits locais que nao estejam no GitHub.
    & git -C $Project merge-base --is-ancestor HEAD "origin/$Branch"

    if ($LASTEXITCODE -ne 0) {

        throw "Historico Git divergente. Processo interrompido para protecao."
    }


    # ========================================================================
    # 7. FOTOGRAFIA DOS ARQUIVOS REMOTOS
    # ========================================================================

    Write-Log ""
    Write-Log "[3/6] Preparando fotografia do GitHub..."

    New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

    $zipPath = Join-Path $TempRoot "remote.zip"

    $remoteDir = Join-Path $TempRoot "remote"

    & git -C $Project archive --format=zip "--output=$zipPath" "origin/$Branch"

    if ($LASTEXITCODE -ne 0) {

        throw "Falha ao preparar arquivos remotos."
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $remoteDir -Force


    # ========================================================================
    # 8. COMPARACAO INDIVIDUAL
    # ========================================================================

    Write-Log ""
    Write-Log "[4/6] Comparando arquivos..."

    $localMap = Get-FileMap $Project

    $remoteMap = Get-FileMap $remoteDir

    $allPaths = @(
        $localMap.Keys + $remoteMap.Keys |
        Sort-Object -Unique
    )

    $sameCount = 0
    $localWins = 0
    $remoteWins = 0
    $protectedMissing = 0
    $tieCount = 0


    foreach ($relativePath in $allPaths) {

        $hasLocal = $localMap.ContainsKey($relativePath)

        $hasRemote = $remoteMap.ContainsKey($relativePath)


        # --------------------------------------------------------------------
        # ARQUIVO EXISTE SOMENTE LOCALMENTE
        # Preservar para posterior envio ao GitHub.
        # --------------------------------------------------------------------

        if ($hasLocal -and -not $hasRemote) {

            $localWins++
            $protectedMissing++

            Write-Log "LOCAL PRESERVADO: $relativePath"

            continue
        }


        # --------------------------------------------------------------------
        # ARQUIVO EXISTE SOMENTE NO GITHUB
        # Baixar para a pasta local.
        # --------------------------------------------------------------------

        if (-not $hasLocal -and $hasRemote) {

            $targetPath = Join-Path $Project $relativePath

            New-Item -ItemType Directory -Force `
                -Path (Split-Path -Parent $targetPath) | Out-Null

            Copy-Item -LiteralPath $remoteMap[$relativePath] `
                -Destination $targetPath -Force

            $remoteWins++

            Write-Log "BAIXADO DO GITHUB: $relativePath"

            continue
        }


        # --------------------------------------------------------------------
        # COMPARACAO SHA-256
        # --------------------------------------------------------------------

        $localPath = $localMap[$relativePath]

        $remotePath = $remoteMap[$relativePath]

        $localHash = (Get-FileHash -LiteralPath $localPath -Algorithm SHA256).Hash

        $remoteHash = (Get-FileHash -LiteralPath $remotePath -Algorithm SHA256).Hash

        if ($localHash -eq $remoteHash) {

            $sameCount++

            continue
        }


        # --------------------------------------------------------------------
        # IDENTIFICAR QUAL LADO FOI ALTERADO
        # --------------------------------------------------------------------

        $gitRelativePath = $relativePath.Replace('\', '/')

        $baseBlob = Get-GitText @(
            "rev-parse", "HEAD:$gitRelativePath"
        )

        $remoteBlob = Get-GitText @(
            "rev-parse", "origin/$Branch`:$gitRelativePath"
        )

        $localBlob = Get-GitText @(
            "hash-object", "--", $localPath
        )

        $localChanged = (-not $baseBlob) -or ($localBlob -ne $baseBlob)

        $remoteChanged = (-not $baseBlob) -or ($remoteBlob -ne $baseBlob)


        # --------------------------------------------------------------------
        # SOMENTE LOCAL ALTERADO
        # --------------------------------------------------------------------

        if ($localChanged -and -not $remoteChanged) {

            $localWins++

            Write-Log "LOCAL PREVALECE: $relativePath"

            continue
        }


        # --------------------------------------------------------------------
        # SOMENTE GITHUB ALTERADO
        # --------------------------------------------------------------------

        if ($remoteChanged -and -not $localChanged) {

            Copy-Item -LiteralPath $remotePath `
                -Destination $localPath -Force

            $remoteWins++

            Write-Log "GITHUB PREVALECE: $relativePath"

            continue
        }


        # --------------------------------------------------------------------
        # AMBOS ALTERADOS: COMPARAR DATAS
        # --------------------------------------------------------------------

        $remoteTimestampText = Get-GitText @(
            "log",
            "-1",
            "--format=%ct",
            "origin/$Branch",
            "--",
            $gitRelativePath
        )

        $remoteTimestamp = 0L

        if ($remoteTimestampText -match '^\d+$') {

            $remoteTimestamp = [long]$remoteTimestampText
        }

        $localTimestamp = [long](
            [DateTimeOffset](
                Get-Item -LiteralPath $localPath
            ).LastWriteTimeUtc
        ).ToUnixTimeSeconds()


        # --------------------------------------------------------------------
        # LOCAL MAIS RECENTE
        # --------------------------------------------------------------------

        if (
            $localTimestamp -gt $remoteTimestamp -and
            $remoteTimestamp -gt 0
        ) {

            $localWins++

            Write-Log "CONFLITO: LOCAL MAIS RECENTE: $relativePath"
        }


        # --------------------------------------------------------------------
        # GITHUB MAIS RECENTE
        # --------------------------------------------------------------------

        elseif ($remoteTimestamp -gt $localTimestamp) {

            Copy-Item -LiteralPath $remotePath `
                -Destination $localPath -Force

            $remoteWins++

            Write-Log "CONFLITO: GITHUB MAIS RECENTE: $relativePath"
        }


        # --------------------------------------------------------------------
        # EMPATE OU DATA INDETERMINADA
        # Preservar a copia local adicionalmente.
        # --------------------------------------------------------------------

        else {

            $conflictCopy = "$localPath.local-conflict-$Stamp"

            Copy-Item -LiteralPath $localPath `
                -Destination $conflictCopy -Force

            Copy-Item -LiteralPath $remotePath `
                -Destination $localPath -Force

            $remoteWins++
            $tieCount++

            Write-Log "EMPATE: COPIA LOCAL PRESERVADA: $conflictCopy"
        }
    }


    # ========================================================================
    # 9. REGISTRAR ALTERACOES NO GIT
    # ========================================================================

    Write-Log ""
    Write-Log "[5/6] Registrando resultado no Git..."

    # Atualiza a base do indice sem apagar os arquivos de trabalho.
    Invoke-Git @("reset", "--mixed", "origin/$Branch")

    # Adiciona arquivos novos e modificados.
    Invoke-Git @("add", "-A")

    & git -C $Project diff --cached --quiet

    if ($LASTEXITCODE -eq 1) {

        Invoke-Git @(
            "commit",
            "-m",
            "Sincronizacao NIMOB $Stamp"
        )
    }
    elseif ($LASTEXITCODE -gt 1) {

        throw "Erro ao verificar alteracoes."
    }
    else {

        Write-Log "Nenhuma alteracao nova para registrar."
    }


    # ========================================================================
    # 10. ENVIAR PARA O GITHUB
    # ========================================================================

    Write-Log ""
    Write-Log "[6/6] Enviando para GitHub..."

    Invoke-Git @(
        "push",
        "-u",
        "origin",
        $Branch
    )


    # ========================================================================
    # 11. RELATORIO FINAL
    # ========================================================================

    Write-Log ""
    Write-Log "============================================================"
    Write-Log "SINCRONIZACAO CONCLUIDA"
    Write-Log "Arquivos iguais: $sameCount"
    Write-Log "Prevalencia local: $localWins"
    Write-Log "Prevalencia GitHub: $remoteWins"
    Write-Log "Arquivos ausentes protegidos: $protectedMissing"
    Write-Log "Empates/datas indeterminadas: $tieCount"
    Write-Log "Backup: $BackupDir"
    Write-Log "Relatorio: $Report"
    Write-Log "============================================================"

}

catch {

    Write-Host ""

    Write-Host "ERRO: $($_.Exception.Message)" -ForegroundColor Red

    if (Test-Path -LiteralPath $Report) {

        Add-Content -LiteralPath $Report `
            -Value ("ERRO: " + $_.Exception.Message) `
            -Encoding UTF8
    }

    Write-Host "Backup: $BackupDir"

    Write-Host "Relatorio: $Report"

    exit 1
}

finally {

    # Remove somente a pasta temporaria desta execucao.
    # Nunca remove o projeto ou os backups.

    if (Test-Path -LiteralPath $TempRoot) {

        Remove-Item -LiteralPath $TempRoot `
            -Recurse -Force -ErrorAction SilentlyContinue
    }
}
