import sys, math
# Autor: Margus Sumla
# 2017

# muutujad
a = None
b = None
c = None
# funktsioonid
def inp():
    return input()

def add(a, b):
    return a + b

def sub(a, b):
    return a - b

def mul(a, b):
    return a * b

def div(a, b):
    return a / b

def pow(a, b):
    return a ** b
    
def sqr(a):
    return math.sqrt(a)

def ans(c, e):
    print("%s %s %s = %.2f" % (a, c, b, e(a, b)))

def ans_(c, e):
    print("Ruutjuur %s-st = %.2f" % (a, e(a)))
# kasutusjuhend
if len(sys.argv) == 2 and sys.argv[1] == 'help':
    print('Kalkulaatori kasutamine:\n'
          '\t1) kasuparameetritega  : sisesta tehte liikmed skripti kaivitamise kasu jarel tyhikutega eraldatult (1.operand [+, -, *, /, ^] 2.operand). Naiteks: python3 calc.py 1 / 200\n'
          '\t2) kasitsi sisestusega : sisesta parameetrid ykshaaval vastavalt kysitule.')

    exit()
# sisestamine
if len(sys.argv) == 4:
    print('Kasutusjuhendi nagemiseks lisa skripti kaivitamise kasu loppu sona help.\n')

    try:
        a = float(sys.argv[1])
        c = str(sys.argv[2])
        b = float(sys.argv[3])
    except:
        print('Vale sisestus!')
        print('Kasutusjuhendi nagemiseks lisa skripti kaivitamise kasu loppu sona help.')
elif len(sys.argv) == 3:
    print('Kasutusjuhendi nagemiseks lisa skripti kaivitamise kasu loppu sona help.\n')

    try:
        a = float(sys.argv[1])
        c = str(sys.argv[2])
    except:
        print('Vale sisestus!')
        print('Kasutusjuhendi nagemiseks lisa skripti kaivitamise kasu loppu sona help.')
else:
    print('Kasutusjuhendi nagemiseks lisa skripti kaivitamise kasu loppu sona help.\n')

    try:
        print('Esimene operand: ')
        a = float(inp())
    except:
        print('Vale sisestus! Kasutada saab taisarve voi komakohaga arve (koma asemel on punkt).')
        print('Kasutusjuhendi nagemiseks lisa skripti kaivitamise kasu loppu sona help.\n')
        exit()

    try:
        print('Tehe: ')
        c = str(inp())
    except:
        print('Vale sisestus! Kasutada saab +, -, *, / voi ^.')
        print('Kasutusjuhendi nagemiseks lisa skripti kaivitamise kasu loppu sona help.\n')
        exit()
    if c != '_':
        try:
            print('Teine operand: ')
            b = float(inp())
        except:
            print('Vale sisestus! Kasutada saab taisarve voi komakohaga arve (koma asemel on punkt).')
            print('Kasutusjuhendi nagemiseks lisa skripti kaivitamise kasu loppu sona help.\n')
            exit()
# tehted
if c == '+':
    ans(c, add)
elif c == '-':
    ans(c, sub)
elif c == '*':
    ans(c, mul)
elif c == '/':
    ans(c, div)
elif c == '^':
    ans(c, pow)
elif c == '_':
    ans_(c, sqr)
else:
    print('Vale sisestus! Kontrolli tehte marki! (Lubatud on +, -, *, /, ^)')
    print('Kasutusjuhendi nagemiseks lisa skripti kaivitamise kasu loppu sona help.\n')