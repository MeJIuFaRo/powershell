#https://winitpro.ru/index.php/2016/11/17/kak-podpisat-skript-powershell-sertifikatom/?ysclid=l7z4ph81ln445590179
$cert = (Get-ChildItem cert:\CurrentUser\my -CodeSigningCert)[0]
Get-ChildItem .\*.ps1 | Set-AuthenticodeSignature -Certificate $Cert