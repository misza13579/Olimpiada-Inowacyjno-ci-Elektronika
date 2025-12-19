import asyncio
import chess
import chess.engine
from bless import (
    BlessServer, 
    BlessGATTCharacteristic, 
    GATTCharacteristicProperties, 
    GATTAttributePermissions
)
from luma.core.interface.serial import spi
from luma.lcd.device import ili9488
from luma.core.render import canvas
from PIL import ImageFont
from RPi import GPIO

# --- KONFIGURACJA ---
SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8"
STOCKFISH_PATH = "/usr/games/stockfish"

class ChessSystem:
    def __init__(self):
        # 1. Konfiguracja przycisków
        self.BTN_WHITE = 19
        self.BTN_BLACK = 5
        GPIO.setmode(GPIO.BCM)
        GPIO.setup(self.BTN_WHITE, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
        GPIO.setup(self.BTN_BLACK, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)

        # 2. Inicjalizacja ekranu
        try:
            serial_interface = spi(port=0, device=0, gpio_DC=27, gpio_RST=17, bus_speed_hz=32000000)
            self.device = ili9488(serial_interface, width=480, height=320, rotate=2) 
            print("--- Ekran zainicjalizowany ---")
        except Exception as e:
            print(f"Błąd ekranu: {e}")
            self.device = None

        # 3. Kolory i Czcionki
        self.C_BEIGE = "#463B2A"      # Tło główne
        self.C_BROWN_D = "#412C28"    # Ciemny brąz (tekst)
        self.C_BROWN_L = "#D18164"    # Jasny brąz (panele)
        self.C_GOLD = "#C6A664"       # Złoty (aktywna tura)

        try:
            self.f_big = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 70)
            self.f_small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 25)
        except:
            self.f_big = self.f_small = ImageFont.load_default()

        # 4. Stan gry
        self.board = chess.Board()
        self.engine = None
        self.elo = 800
        self.white_time = 600
        self.black_time = 600
        self.current_turn = chess.WHITE
        self.game_active = False

    def draw_clock(self):
        if not self.device: return
        
        with canvas(self.device) as draw:
            # Tło
            draw.rectangle((0, 0, 480, 320), fill=self.C_BEIGE)
            
            # Obramowania zależne od tury
            w_outline = self.C_GOLD if self.current_turn == chess.WHITE else self.C_BROWN_D
            b_outline = self.C_GOLD if self.current_turn == chess.BLACK else self.C_BROWN_D

            # Panel GRACZ (Białe)
            draw.rectangle((10, 10, 470, 150), fill=self.C_BROWN_L, outline=w_outline, width=5)
            draw.text((30, 25), "GRACZ", fill=self.C_BROWN_D, font=self.f_small)
            wm, ws = divmod(int(self.white_time), 60)
            draw.text((150, 45), f"{wm:02d}:{ws:02d}", fill=self.C_BROWN_D, font=self.f_big)

            # Panel BOT (Czarne)
            draw.rectangle((10, 160, 470, 300), fill=self.C_BROWN_L, outline=b_outline, width=5)
            draw.text((30, 175), f"BOT [ELO {self.elo}]", fill=self.C_BROWN_D, font=self.f_small)
            bm, bs = divmod(int(self.black_time), 60)
            draw.text((150, 195), f"{bm:02d}:{bs:02d}", fill=self.C_BROWN_D, font=self.f_big)

            if not self.game_active:
                draw.text((330, 15), "POŁĄCZ...", fill="red", font=self.f_small)

    async def update_timer(self):
        while True:
            if self.game_active:
                if self.current_turn == chess.WHITE and self.white_time > 0:
                    self.white_time -= 1
                elif self.current_turn == chess.BLACK and self.black_time > 0:
                    self.black_time -= 1
                
                if self.white_time <= 0 or self.black_time <= 0:
                    self.game_active = False
                self.draw_clock()
            await asyncio.sleep(1)

    async def watch_buttons(self):
        """Obsługa fizycznych przycisków - na razie tylko przełączają czas"""
        while True:
            if self.game_active:
                # Przycisk Białych (Pin 35)
                if GPIO.input(self.BTN_WHITE) == GPIO.HIGH and self.current_turn == chess.WHITE:
                    self.current_turn = chess.BLACK
                    self.draw_clock()
                    await asyncio.sleep(0.5) # Debouncing

                # Przycisk Czarnych (Pin 29)
                elif GPIO.input(self.BTN_BLACK) == GPIO.HIGH and self.current_turn == chess.BLACK:
                    self.current_turn = chess.WHITE
                    self.draw_clock()
                    await asyncio.sleep(0.5)
            await asyncio.sleep(0.05)

    def start_new_game(self, elo, minutes):
        self.elo = elo
        self.white_time = minutes * 60
        self.black_time = minutes * 60
        self.board.reset()
        self.game_active = True
        self.current_turn = chess.WHITE
        print(f"Nowa gra: {minutes} min, ELO {elo}")
        self.draw_clock()

async def run_server():
    sys = ChessSystem()
    server = BlessServer(name="Chess_RPi")

    def on_write(characteristic, value):
        data = value.decode("utf-8")
        print(f"Odebrano: {data}")

        if data.startswith("START_GAME:ELO:"):
            try:

                parts = data.split(":")
                elo_val = int(parts[2])
                time_val = int(parts[4])
                sys.start_new_game(elo_val, time_val)
            except Exception as e:
                print(f"Błąd startu: {e}")

    server.write_request_func = on_write
    await server.add_new_service(SERVICE_UUID)
    await server.add_new_characteristic(
        SERVICE_UUID, CHARACTERISTIC_UUID,
        GATTCharacteristicProperties.read | GATTCharacteristicProperties.write | GATTCharacteristicProperties.notify,
        None, GATTAttributePermissions.readable | GATTAttributePermissions.writeable
    )

    await server.start()
    asyncio.create_task(sys.update_timer())
    asyncio.create_task(sys.watch_buttons())
    sys.draw_clock()
    print("SERWER SZACHOWY DZIAŁA")

    while True:
        await asyncio.sleep(1)

if __name__ == "__main__":
    try:
        asyncio.run(run_server())
    except KeyboardInterrupt:
        GPIO.cleanup()
