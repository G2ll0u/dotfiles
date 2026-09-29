#!/usr/bin/env python3
"""
Persona-themed Process Killer Daemon
Surveille la RAM système via psutil, détecte le processus le plus gourmand dès que RAM > 80%,
déclenche l'embuscade (pause média + son), émet un signal D-Bus et expose une méthode de SIGKILL.
"""

import os
import sys
import time
import signal
import argparse
import subprocess
from pathlib import Path

import psutil
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

DBUS_BUS_NAME = "org.persona.ProcessKiller"
DBUS_OBJECT_PATH = "/org/persona/ProcessKiller"
DBUS_INTERFACE = "org.persona.ProcessKiller"

# Liste des binaires intouchables (immunité divine)
PROTECTED_PROCESSES = {
    "hyprland", "quickshell", "qs", "pipewire", "wireplumber",
    "systemd", "dbus-daemon", "python3", "xwayland", "kitty", "foot"
}

class ProcessKillerService(dbus.service.Object):
    def __init__(self, bus, threshold=80.0, check_interval=2, cooldown=20):
        self.bus = bus
        self.threshold = float(threshold)
        self.check_interval = int(check_interval)
        self.cooldown = int(cooldown)
        self.last_trigger_time = 0.0
        self.active_ambush_pid = None
        
        bus_name = dbus.service.BusName(DBUS_BUS_NAME, bus)
        super().__init__(bus_name, DBUS_OBJECT_PATH)
        print(f"[PersonaKiller] Daemon initialisé sur D-Bus '{DBUS_BUS_NAME}'")
        print(f"[PersonaKiller] Seuil RAM : {self.threshold}% | Intervalle : {self.check_interval}s | Cooldown : {self.cooldown}s")

    # ─────────────────────────────────────────────────────────────
    # D-Bus Signals
    # ─────────────────────────────────────────────────────────────

    @dbus.service.signal(DBUS_INTERFACE, signature="isdddd")
    def AmbushTriggered(self, pid, name, memory_mb, cpu_percent, total_ram_mb, ram_percent):
        """
        Signal émis lors d'un dépassement de seuil RAM.
        Signature: isdddd (int pid, str name, double memory_mb, double cpu_percent, double total_ram_mb, double ram_percent)
        """
        print(f"[PersonaKiller] Signal AmbushTriggered émis -> PID: {pid}, Name: {name}, Mem: {memory_mb:.1f}MB, RAM: {ram_percent:.1f}%")

    @dbus.service.signal(DBUS_INTERFACE, signature="isb")
    def ProcessKilled(self, pid, name, success):
        """Signal émis après tentative de kill."""
        print(f"[PersonaKiller] Signal ProcessKilled émis -> PID: {pid}, Name: {name}, Success: {success}")

    # ─────────────────────────────────────────────────────────────
    # D-Bus Methods
    # ─────────────────────────────────────────────────────────────

    @dbus.service.method(DBUS_INTERFACE, in_signature="i", out_signature="bs")
    def KillProcess(self, pid):
        """
        Exécute os.kill(pid, signal.SIGKILL) avec confirmation.
        Retourne (success: bool, message: str)
        """
        pid = int(pid)
        print(f"[PersonaKiller] Requête D-Bus KillProcess reçue pour le PID {pid}")
        
        if pid <= 1 or pid == os.getpid():
            return False, f"Action refusée : Impossible de tuer le PID {pid} critique système."

        proc_name = "inconnu"
        try:
            p = psutil.Process(pid)
            proc_name = p.name()
            if proc_name.lower() in PROTECTED_PROCESSES:
                return False, f"Action refusée : Le processus '{proc_name}' (PID {pid}) est protégé par le système."
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

        try:
            os.kill(pid, signal.SIGKILL)
            self.active_ambush_pid = None
            self.ProcessKilled(pid, proc_name, True)
            return True, f"ALL-OUT ATTACK réussi : Processus '{proc_name}' (PID {pid}) éliminé."
        except ProcessLookupError:
            self.ProcessKilled(pid, proc_name, False)
            return False, f"Erreur : Le processus {pid} n'existe plus."
        except PermissionError:
            self.ProcessKilled(pid, proc_name, False)
            return False, f"Erreur de permission : Droits insuffisants pour SIGKILL sur PID {pid}."
        except Exception as e:
            self.ProcessKilled(pid, proc_name, False)
            return False, f"Erreur inattendue : {str(e)}"

    @dbus.service.method(DBUS_INTERFACE, in_signature="", out_signature="bs")
    def TriggerAmbush(self):
        """Déclenche manuellement l'embuscade pour test."""
        print("[PersonaKiller] Déclenchement manuel de l'embuscade demandé via D-Bus")
        top_proc = self._get_top_memory_process()
        if not top_proc:
            return False, "Aucun processus utilisateur trouvé."
        
        self._trigger_ambush_sequence(top_proc)
        return True, f"Embuscade déclenchée contre {top_proc['name']} (PID {top_proc['pid']})"

    @dbus.service.method(DBUS_INTERFACE, in_signature="", out_signature="a{sv}")
    def GetStatus(self):
        """Retourne l'état actuel de la RAM et le top process."""
        vmem = psutil.virtual_memory()
        top_proc = self._get_top_memory_process() or {}
        return {
            "ram_percent": dbus.Double(vmem.percent),
            "ram_used_mb": dbus.Double(vmem.used / (1024 * 1024)),
            "ram_total_mb": dbus.Double(vmem.total / (1024 * 1024)),
            "top_pid": dbus.Int32(top_proc.get("pid", 0)),
            "top_name": dbus.String(top_proc.get("name", "")),
            "top_memory_mb": dbus.Double(top_proc.get("memory_mb", 0.0)),
        }

    # ─────────────────────────────────────────────────────────────
    # Internal Logic & Monitoring Loop
    # ─────────────────────────────────────────────────────────────

    def _get_top_memory_process(self):
        """Récupère le processus le plus consommateur de mémoire (RSS)."""
        candidates = []
        my_pid = os.getpid()

        for proc in psutil.process_iter(['pid', 'name', 'memory_info', 'cpu_percent']):
            try:
                info = proc.info
                pid = info['pid']
                name = (info['name'] or f"pid_{pid}").strip()
                # Ignore system idle / self / processus protégés
                if pid <= 1 or pid == my_pid:
                    continue
                if name.lower() in PROTECTED_PROCESSES:
                    continue
                rss = info['memory_info'].rss if info['memory_info'] else 0
                candidates.append({
                    "pid": pid,
                    "name": name,
                    "memory_mb": float(rss) / (1024 * 1024),
                    "cpu_percent": float(info['cpu_percent'] or 0.0),
                })
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                continue

        if not candidates:
            return None

        # Trier par mémoire RSS descendante
        candidates.sort(key=lambda x: x["memory_mb"], reverse=True)
        return candidates[0]

    def _trigger_ambush_sequence(self, top_proc):
        """Exécute l'effet d'embuscade audio/média et émet le signal D-Bus."""
        now = time.time()
        self.last_trigger_time = now
        self.active_ambush_pid = top_proc["pid"]

        # 1. Pause multimédia immédiate
        try:
            subprocess.run(["playerctl", "-a", "pause"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            pass

        # 2. Joue l'effet sonore / musique via ambush.sh ou pw-play
        script_dir = Path(__file__).resolve().parent
        ambush_script = script_dir / "ambush.sh"
        audio_file = script_dir / "assets" / "mass_destruction_intro.ogg"

        if ambush_script.exists() and os.access(ambush_script, os.X_OK):
            subprocess.Popen([str(ambush_script)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif audio_file.exists():
            subprocess.Popen(["pw-play", str(audio_file)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        # 3. Émission du signal D-Bus
        vmem = psutil.virtual_memory()
        total_ram_mb = float(vmem.total) / (1024 * 1024)
        ram_percent = float(vmem.percent)

        self.AmbushTriggered(
            int(top_proc["pid"]),
            str(top_proc["name"]),
            float(top_proc["memory_mb"]),
            float(top_proc["cpu_percent"]),
            float(total_ram_mb),
            float(ram_percent)
        )

        # 4. Envoi optionnel direct à Quickshell IPC pour ultra-réactivité
        try:
            subprocess.Popen([
                "qs", "ipc", "call", "persona_killer", "trigger",
                str(top_proc["pid"]),
                str(top_proc["name"]),
                f"{top_proc['memory_mb']:.1f}",
                f"{top_proc['cpu_percent']:.1f}",
                f"{total_ram_mb:.1f}",
                f"{ram_percent:.1f}"
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            pass

    def check_memory(self):
        """Timer callback de surveillance."""
        try:
            vmem = psutil.virtual_memory()
            now = time.time()

            if vmem.percent >= self.threshold:
                if (now - self.last_trigger_time) >= self.cooldown:
                    top_proc = self._get_top_memory_process()
                    if top_proc:
                        print(f"[PersonaKiller] ALERTE : RAM critique à {vmem.percent:.1f}% >= {self.threshold}%")
                        print(f"[PersonaKiller] Cible détectée : {top_proc['name']} (PID {top_proc['pid']}) utilisant {top_proc['memory_mb']:.1f} MB")
                        self._trigger_ambush_sequence(top_proc)
            else:
                # Si la RAM repasse sous le seuil, on reset l'état actif
                if self.active_ambush_pid is not None:
                    self.active_ambush_pid = None
        except Exception as e:
            print(f"[PersonaKiller] Erreur dans check_memory : {e}", file=sys.stderr)

        return True  # Pour que GLib.timeout continue de boucler


def main():
    parser = argparse.ArgumentParser(description="Persona Process Killer D-Bus Daemon")
    parser.add_argument("--threshold", type=float, default=80.0, help="Seuil de déclenchement RAM en %% (défaut: 80.0)")
    parser.add_argument("--interval", type=int, default=2, help="Intervalle de vérification en secondes (défaut: 2)")
    parser.add_argument("--cooldown", type=int, default=20, help="Délai minimal entre deux alertes en secondes (défaut: 20)")
    parser.add_argument("--trigger", action="store_true", help="Déclenche immédiatement l'embuscade (manuellement) et quitte")
    args = parser.parse_args()

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    session_bus = dbus.SessionBus()

    # Si l'utilisateur demande seulement à déclencher l'embuscade
    if args.trigger:
        try:
            proxy = session_bus.get_object(DBUS_BUS_NAME, DBUS_OBJECT_PATH)
            iface = dbus.Interface(proxy, DBUS_INTERFACE)
            success, msg = iface.TriggerAmbush()
            print(f"[PersonaKiller] {msg}")
            return
        except dbus.DBusException:
            # Si le daemon n'est pas actif, on effectue l'embuscade directement en mode standalone
            service = ProcessKillerService(session_bus, threshold=0)
            top_proc = service._get_top_memory_process()
            if top_proc:
                service._trigger_ambush_sequence(top_proc)
                print(f"[PersonaKiller] Embuscade déclenchée (mode direct) contre {top_proc['name']} (PID {top_proc['pid']})")
            else:
                print("[PersonaKiller] Aucun processus trouvé.")
            return

    service = ProcessKillerService(
        session_bus,
        threshold=args.threshold,
        check_interval=args.interval,
        cooldown=args.cooldown
    )

    # Enregistrement du timer GLib
    GLib.timeout_add_seconds(args.interval, service.check_memory)

    loop = GLib.MainLoop()
    
    def shutdown(sig, frame):
        print("\n[PersonaKiller] Arrêt du daemon...")
        loop.quit()

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    print("[PersonaKiller] Daemon démarré. En attente d'événements...")
    loop.run()


if __name__ == "__main__":
    main()
