# -*- coding: utf-8 -*-
#
# Created by Margus Sumla
#
# -="ÕIS'i hinnete automaatne kontroll ja e-maili saatmine hinde muutumisel"=-
#
# Vajalikud lisateegid: bs4, python3-lxml
#
# Käsu käivitamise järgi saab anda ühe argumendi, mis on otsitava (osaline) 
# testi/eksami/töö nimetus. Seejärel tuleb ÕIS-i ning emaili autentimise osa
# ("no" puhul kasutatakse vaikimisi emaili saatmise seadeid) ja siis emaili
# teavituse saamise aadressi sisestus. Viimaks tuleb seadistada hindekontrolli
# sagedus (vaikimisi pool tundi, et ÕIS-i sessioonidega mitte üle koormata).
#
# Edasijõudnutele: sisesta vajalikud parameetrid käsu järgi ja lisa lõppu "&",
# et skript saaks taustprotsessina töötada.
# Käsujärgsete parameetrite järjekord:
#   1) otsitava töö hinde nimetus ('' puhul kontrollitakse kõiki hindeid),
#   2) ÕIS-i kasutajatunnus,
#   3) ÕIS-i parool,
#   4) emaili aadress, kuhu saata tulemus,
#   5) kui mitme sekundi järel hinnet uuesti kontrollitakse.
# Näiteks: python3 hinne.py eksam minuõisikasutaja minuõisiparool minuemail@gmail.com 3600 &
# Protsessi lõpetamiseks on vajalik "kill [-9] <protsessi id>" või "killall python3" käsk.
#
# P.S. Kuna hinded vahetuvad ÕIS-is harva, siis on lisatud skriptile testimise võimalus.
# Selleks tuleb logida ÕIS-i sisse ja "Minu hinded" lehel teha teine hiireklõps ning
# salvestada endale selle (html) lähtekood. Seejärel saab käivitada skripti ja ise käsitsi
# teha lähtekoodi failis vastavaid muudatusi (nagu õppejõud oleks hinnet lisanud/muutnud).
# Testskripti käivitamise näide: python3 hinne.py '' minuemail@gmail.com 10 test hinded.txt
#
import os, sys, getpass
import requests
from bs4 import BeautifulSoup
import smtplib
from time import sleep

def clear_():
    try:
        os.system('clear')
    except:
        os.system('cls')

def get_interval_():
    try:
        interval_ = float(input('Interval to check grades after (press enter for default (1800 seconds)): '))
    except:
        interval_ = 1800.0

    return interval_

def mail_auth():
    dec = ''

    while dec != 'yes' and dec != 'no':
        dec = input('Do you wish to setup a g-mail account (no for default account)? [ yes / no ]: ').lower()

    if dec == 'yes':
        print('Make sure of "Allow less secure apps: ON" in gmail settings.')
        return [input('Gmail username: '), getpass.getpass('Gmail password: '), input('Send notifications to email: ')]
    else:
        return ['ambaaigar', 'r4g144bm4', input('Send notifications to email: ')]

def send_mail(auth, msg):
    mail_user = auth[0]
    mail_pass = auth[1]
    mail_send_to = auth[2]

    server = smtplib.SMTP('smtp.gmail.com', 587)
    server.starttls()

    try:
        server.login(mail_user, mail_pass)
    except:
        server.login('ambaaigar', 'r4g144bm4')
        mail_user = 'ambaaigar'

    server.sendmail(mail_user, mail_send_to, msg)
    server.quit()
    print('Email sent to ' + auth[2])

def ois_auth():
    username = input('ÕIS username: ')
    password = getpass.getpass('ÕIS password: ')
    return [username, password]

def get_grades(auth, task):
    items = []
    tasks = []
    task = task.lower()
    username = auth[0]
    password = auth[1]
    student_id = ''

    s = requests.Session()

    r = s.post('https://itcollege.ois.ee/auth/login', data={'username': username,
                                                            'pw': password,
                                                            'continue': '/',
                                                            'Login': 'Logi sisse'})

    for line in s.get('https://itcollege.ois.ee'):
        line = str(line)

        if 'student_id=' in line:
            start_ = line.find('student_id=') + len('student_id=')
            student_id = line[start_:start_ + 4]
            break

    html = s.get('https://itcollege.ois.ee/grade?student_id=' + student_id)

    s.close()

    try:
        json = [[cell.text for cell in row('td')] for row in BeautifulSoup(html.text, 'lxml')('tr')]
    except:
        json = [[cell.text for cell in row('td')] for row in BeautifulSoup(html.text, 'html5lib')('tr')]

    return grade_parser(json, task)

def get_grades_test(file_, task):
    task = task.lower()

    html = open(file_, encoding='ISO-8859-1')

    try:
        json = [[cell.text for cell in row('td')] for row in BeautifulSoup(html.read(), 'html5lib')('tr')]
    except:
        json = [[cell.text for cell in row('td')] for row in BeautifulSoup(html.read(), 'lxml')('tr')]

    html.close()

    return grade_parser(json, task)

def grade_parser(json_, task_):
    items = []
    tasks = []
    
    for i in range(len(json_)):
        if len(json_[i]) > 3:
            subjects = json_[i]

        if len(json_[i]) == 2:
            items.append(json_[i])

    for i in range(len(items)):
        items[i][0] = items[i][0].replace('\n', '').lower().strip(' ')
        items[i][1] = items[i][1].replace('\n', '').replace(' ', '')

        while '  ' in items[i][0]:
            items[i][0] = items[i][0].replace('  ', ' ')[1:]

    for i in items:
        if task_ in i[0]:
            tasks.append(items[items.index(i)])
            
    return tasks
    
def track_grade(grades, cnt, interval_):
    count = 0
    counting_ = int(interval_)
    
    try:
        grades_ = get_grades(auth, line_in1)
    except:
        grades_ = get_grades_test(sys.argv[5], line_in1)

    for g in range(len(grades)):
        if grades[g][1] == grades_[g][1]:
            count += 1
        else:
            count = 0
            grade = grades_[g][0].encode('ascii', 'replace').decode('ascii') + grades_[g][1]
            break

    if count == len(grades):
        cnt += 1

        for i in range(int(counting_ / 5)):
            clear_()
            print('Grade "' + line_in1 + '" has not changed yet (tries: ' + str(cnt) + '). Trying again in ' + str(counting_) + ' seconds ..')
            sleep(5)
            counting_ -= 5

        track_grade(grades, cnt, interval_)
    else:
        clear_()
        time_ran = int(cnt * interval_ / 60)

        if time_ran == 1:
            print('The grade has finally changed (script ran for ' + str(time_ran) + ' minute).\n\nResult: "' + grade + '"\n')
        elif time_ran == 0:
            print('The grade has finally changed (script ran for less than a minute).\n\nResult: "' + grade + '"\n')
        else:
            print('The grade has finally changed (script ran for ' + str(time_ran) + ' minutes).\n\nResult: "' + grade + '"\n')

        send_mail(auth_, grade)

clear_()

if len(sys.argv) == 6:
    if sys.argv[4] == 'test':
        line_in1 = sys.argv[1]

        auth_ = ['ambaaigar', 'r4g144bm4', sys.argv[2]]
        
        interval_ = float(sys.argv[3])
        
        grades = get_grades_test(sys.argv[5], line_in1)

        track_grade(grades, 0, interval_)
    else:
        line_in1 = sys.argv[1]

        auth = [sys.argv[2], sys.argv[3]]
        grades = get_grades(auth, line_in1)

        auth_ = ['ambaaigar', 'r4g144bm4', sys.argv[4]]

        interval_ = float(sys.argv[5])

        track_grade(grades, 0, interval_)
elif len(sys.argv) <= 2:
    try:
        line_in1 = sys.argv[1]
    except:
        line_in1 = input('Enter the assignment which you want to track, listed in "ÕIS hinded".\n(Input is case insensitive and could only be a part of the assingment\'s name.\nPress enter to scan all grades, the first one changed will be notified.): ')

    auth = ois_auth()
    grades = get_grades(auth, line_in1)

    auth_ = mail_auth()

    interval_ = get_interval_()

    track_grade(grades, 0, interval_)