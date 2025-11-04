# FH_to_HW
Migracao de ONU de OLT Fiberhome (=> RP1000) para Olt Huawei (MA5800)

1 - Efetuar Backup da Olt gerando arquivo .cfg ex. fh1.cfg

2 - Exportar onu via unm2000 com informacoes Device Name, Slot Number, Pon Number Onu Number, Pyhysical Address, ex.fh1.csv, caso precise mudar a uplink da olt huawei apra gerar as vlan altere a linha ( hw_uplink="0/8 0" )

<img width="535" height="50" alt="Captura de imagem_20250806_104147" src="https://github.com/user-attachments/assets/639e4233-0722-44c0-802c-803649f1db80" />



3- De Permissao de execultar "chmod +x fh_hw.sh" , execulte fh_hw.sh fh1.csv fh1.cfg QINQPROFILE (opcional)

<img width="396" height="45" alt="Captura de imagem_20250806_105525" src="https://github.com/user-attachments/assets/5442ad56-e782-4c84-b13c-b0dd4cabb7ca" />






O comando extrai vlan, slot, pon do physical address informado no .csv.
Provisionamento

<img width="593" height="64" alt="image" src="https://github.com/user-attachments/assets/3a04c91d-40d8-4219-a43b-29b46b56ccd3" />





Vlans para add na olt

<img width="223" height="423" alt="Captura de imagem_20250806_105058" src="https://github.com/user-attachments/assets/da6afa9b-9b5f-48aa-80dd-042b9fb3d865" />





Service Profiles

<img width="842" height="181" alt="Captura de imagem_20250806_105146" src="https://github.com/user-attachments/assets/ebc2f545-ec23-4d3f-8d08-d0ca8871f591" />



Ont Profiles

<img width="330" height="181" alt="Captura de imagem_20250806_105217" src="https://github.com/user-attachments/assets/716f95a1-2077-4ccf-922b-539c55b83fe0" />
