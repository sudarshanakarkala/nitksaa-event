# test_email.py

import smtplib

server = smtplib.SMTP("smtp.gmail.com", 587)
server.starttls()

server.login(
    "sudarshana.karkala@gmail.com",
    "pustdxaroqrsiuqu"
)

print("SMTP Login Success")

server.quit()