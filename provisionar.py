import argparse
import time
from netmiko import ConnectHandler

def aplicar_arquivo(session, file_path):
    try:
        print(f"📄 Lendo: {file_path}")
        with open(file_path, 'r') as f:
            # Filtra linhas vazias ou comentários
            comandos = [linha.strip() for linha in f if linha.strip() and not linha.startswith('#')]
        
        if not comandos:
            print(f"⚠️ Arquivo {file_path} está vazio. Pulando...")
            return

        print(f"⚙️ Aplicando {len(comandos)} comandos...")
        # send_config_set é ideal para grandes volumes
        output = session.send_config_set(comandos)
        print(f"✅ Concluído: {file_path}")
        return output
    except FileNotFoundError:
        print(f"❌ Arquivo não encontrado: {file_path}")
    except Exception as e:
        print(f"❌ Erro ao processar {file_path}: {e}")

def main():
    parser = argparse.ArgumentParser(description='Auto-Deploy OLT Huawei')
    parser.add_argument('-ip', required=True, help='IP da OLT')
    parser.add_argument('-u', required=True, help='Usuário')
    parser.add_argument('-p', required=True, help='Senha')
    parser.add_argument('-m', choices=['S', 'T'], required=True, help='S=SSH, T=Telnet')
    
    args = parser.parse_args()

    device = {
        'device_type': 'huawei' if args.m == 'S' else 'huawei_telnet',
        'host': args.ip,
        'username': args.u,
        'password': args.p,
        'port': 22 if args.m == 'S' else 23,
        'global_delay_factor': 2, # Aumenta o timeout para OLTs lentas
    }

    try:
        print(f"🔌 Conectando em {args.ip}...")
        with ConnectHandler(**device) as session:
            session.enable()
            
            # ORDEM CRÍTICA DE EXECUÇÃO
            arquivos = ['add_vlans.txt', 'saida.txt', 'add_service.txt']
            
            for arq in arquivos:
                aplicar_arquivo(session, arq)
                print("⏳ Aguardando 2 segundos para sincronização do buffer...")
                time.sleep(2)

            print("💾 Salvando configuração na OLT...")
            session.send_command("save")
            print("🚀 Migração finalizada com sucesso!")

    except Exception as e:
        print(f"❌ Erro na conexão: {e}")

if __name__ == "__main__":
    main()
