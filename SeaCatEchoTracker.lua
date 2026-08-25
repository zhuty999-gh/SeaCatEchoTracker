local addonName, ns = ...

SeaCatEchoTrackerDB = SeaCatEchoTrackerDB or {}

-- One-time import from the upstream addon (Lazoro's EchoTracker), so anyone
-- switching over keeps their layout instead of reconfiguring from scratch.
--
-- EchoTrackerDB is deliberately NOT declared in our .toc. Claiming another
-- addon's saved variable stopped our own from being restored at load. The
-- global is still readable here when the original addon is installed, because
-- "EchoTracker" sorts before "SeaCatEchoTracker" and so loads first.
if not next(SeaCatEchoTrackerDB) and type(EchoTrackerDB) == "table" and next(EchoTrackerDB) then
  local function deepCopy(src)
    local out = {}
    for k, v in pairs(src) do
      if type(v) == "table" then
        out[k] = deepCopy(v)
      else
        out[k] = v
      end
    end
    return out
  end

  SeaCatEchoTrackerDB = deepCopy(EchoTrackerDB)
end

local ECHO_ICON = 4622456
local ECHO_SPELL_ID = 364343
local TEMPORAL_ANOMALY_SPELL_ID = 373861
local LIVING_FLAME_SPELL_ID = 361469
local EMERALD_BLOSSOM_SPELL_ID = 355913

-- Temporal Anomaly's orb applies Echo to the first 5 allies it passes through.
-- In a 20-man raid it reliably clips 5, which is why the count defaults to raid
-- instances only (see ShouldShowCount).
local TEMPORAL_ANOMALY_TARGETS = 5

-- Talent 1242031: casting Emerald Blossom grants buff 1242759, and each stack
-- makes the next Echo land on one additional ally. Stacks cap at 2 and last 15s.
-- Emerald Blossom itself does not consume Echo, so it is absent from the tables
-- below on purpose.
local EXTRA_TARGET_MAX_STACKS = 2
local EXTRA_TARGET_DURATION = 15

-- Echo's real duration is read from a live aura during out-of-combat calibration
-- (see CalibrateDuration). This is only the pre-calibration fallback: base 15s,
-- and talent 376240 adds 15% per point (2 points max), so the true value lands
-- between 15 and 19.5. Starting low keeps the untuned timer on the safe side.
local ECHO_DURATION_FALLBACK = 15

local APPLY_SPELLS = {
  [ECHO_SPELL_ID] = "single",
  [TEMPORAL_ANOMALY_SPELL_ID] = "batch",
}

-- Empowered spells fire UNIT_SPELLCAST_SUCCEEDED when the cast *begins*, so they
-- must be settled on UNIT_SPELLCAST_EMPOWER_STOP instead, which reports whether
-- the channel actually completed. Any empowered spell added to the tables below
-- has to be listed here too, or cancelling its channel will still consume Echo.
local EMPOWERED_SPELLS = {
  [355936] = true, -- Dream Breath
}

-- All active Echoes are consumed together, so these only need to clear the set.
local CONSUME_SPELLS = {
  [366155] = "always",   -- Reversion
  [1256581] = "always",  -- verified in-game via /et spells
  [360995] = "always",   -- Verdant Embrace
  [355936] = "always",   -- Dream Breath
  [LIVING_FLAME_SPELL_ID] = "friendly",
}
local unpackFunc = unpack or table.unpack

-- Aura timing fields carry SecretWhenAurasRestricted, so in combat/encounters/
-- M+/PvP they become secret values. Comparing, doing math on, or formatting a
-- secret throws, so every read of them has to be gated on this.
local function IsSecret(value)
  if not issecretvalue then
    return false
  end
  local ok, secret = pcall(issecretvalue, value)
  return ok and secret and true or false
end

-- STANDARD_TEXT_FONT is nil in some clients/locales; keep a real path around.
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
if type(STANDARD_TEXT_FONT) ~= "string" or STANDARD_TEXT_FONT == "" then
  STANDARD_TEXT_FONT = (GameFontNormal and GameFontNormal:GetFont()) or FALLBACK_FONT
end

local locale = GetLocale()
local L = {}

local function AddTranslations(tbl)
  for k, v in pairs(tbl) do
    L[k] = v
  end
end

if locale == "deDE" then
  AddTranslations({
    ["Echo Tracker"] = "Echo Tracker",
    ["Drag window to move"] = "Fenster ziehen, um es zu bewegen",
    ["General"] = "Allgemein",
    ["Style"] = "Stil",
    ["Text"] = "Text",
    ["Alerts"] = "Warnungen",
    ["Sound"] = "Sound",
    ["Frame"] = "Rahmen",
    ["Icon Size"] = "Symbolgröße",
    ["Unlock Frame"] = "Rahmen entsperren",
    ["Lock Frame"] = "Rahmen sperren",
    ["Always Show"] = "Immer anzeigen",
    ["Minimap"] = "Minikarte",
    ["Hide Minimap Button"] = "Minikarten-Schaltfläche ausblenden",
    ["Tip: drag the minimap button to reposition it."] = "Tipp: Ziehe den Minikartenknopf, um ihn neu zu positionieren.",
    ["Font"] = "Schriftart",
    ["Colors"] = "Farben",
    ["Count Color"] = "Zählerfarbe",
    ["Timer Color"] = "Timerfarbe",
    ["Click a color row to open the palette."] = "Klicke auf eine Farbzeile, um die Palette zu öffnen.",
    ["Count Text"] = "Zählertext",
    ["Count Size"] = "Zählergröße",
    ["Count X"] = "Zähler X",
    ["Count Y"] = "Zähler Y",
    ["Timer Text"] = "Timertext",
    ["Timer Size"] = "Timergröße",
    ["Timer X"] = "Timer X",
    ["Timer Y"] = "Timer Y",
    ["Text auto-scales with icon size. Size sliders fine-tune that scaling."] = "Der Text skaliert automatisch mit der Symbolgröße. Mit den Schiebereglern kannst du die Skalierung feinabstimmen.",
    ["Expiration Alerts"] = "Ablaufwarnungen",
    ["Enable Expiration Alerts"] = "Ablaufwarnungen aktivieren",
    ["Alert Threshold (seconds)"] = "Warnschwelle (Sekunden)",
    ["Alert Text Color"] = "Warntextfarbe",
    ["Glow Color"] = "Leuchtfarbe",
    ["WeakAura-Style Glow"] = "Glow im WeakAura-Stil",
    ["Pulse Animation"] = "Pulsanimation",
    ["Sound options moved to the Sound tab for a cleaner layout."] = "Soundoptionen wurden für ein übersichtlicheres Layout in den Sound-Tab verschoben.",
    ["Alert Sound"] = "Warnsound",
    ["Bell Toll Sound"] = "Glockenklang",
    ["Only Play Once Per Alert Window"] = "Nur einmal pro Warnfenster abspielen",
    ["Repeat Every (seconds)"] = "Wiederholen alle (Sekunden)",
    ["Sound Channel"] = "Soundkanal",
    ["Master"] = "Master",
    ["SFX"] = "SFX",
    ["Ambience"] = "Umgebung",
    ["Dialog"] = "Dialog",
    ["Talking Head"] = "Talking Head",
    ["Uses Bell Toll. Test it below and pick the channel you want."] = "Verwendet Glockenklang. Teste ihn unten und wähle den gewünschten Kanal.",
    ["Test Sound"] = "Sound testen",
    ["Reset to Defaults"] = "Auf Standard zurücksetzen",
    ["Live Preview"] = "Live-Vorschau",
    ["Echo Preview"] = "Echo-Vorschau",
    ["Large number: Echo count"] = "Große Zahl: Echo-Anzahl",
    ["Small number: lowest Echo duration"] = "Kleine Zahl: niedrigste Echo-Dauer",
    ["Updates as you change text, size, font, and color."] = "Aktualisiert sich, wenn du Text, Größe, Schriftart und Farbe änderst.",
    ["Left Click: Open settings"] = "Linksklick: Einstellungen öffnen",
    ["Drag: Move minimap button"] = "Ziehen: Minikartenknopf bewegen",
    ["Right Click: Close settings"] = "Rechtsklick: Einstellungen schließen",
    ["commands:"] = "Befehle:",
    ["toggle settings"] = "Einstellungen umschalten",
    ["enable always show"] = "Immer anzeigen aktivieren",
    ["disable always show"] = "Immer anzeigen deaktivieren",
    ["unlock tracker frame"] = "Tracker-Rahmen entsperren",
    ["lock tracker frame"] = "Tracker-Rahmen sperren",
    ["reset settings to defaults"] = "Einstellungen zurücksetzen",
    ["Alerts are configurable in the Alerts tab."] = "Warnungen können im Warnungen-Tab konfiguriert werden.",
    ["Default"] = "Standard",
  })
elseif locale == "frFR" then
  AddTranslations({
    ["Echo Tracker"] = "Echo Tracker",
    ["Drag window to move"] = "Faites glisser la fenêtre pour la déplacer",
    ["General"] = "Général",
    ["Style"] = "Style",
    ["Text"] = "Texte",
    ["Alerts"] = "Alertes",
    ["Sound"] = "Son",
    ["Frame"] = "Cadre",
    ["Icon Size"] = "Taille de l’icône",
    ["Unlock Frame"] = "Déverrouiller le cadre",
    ["Lock Frame"] = "Verrouiller le cadre",
    ["Always Show"] = "Toujours afficher",
    ["Minimap"] = "Mini-carte",
    ["Hide Minimap Button"] = "Masquer le bouton de la mini-carte",
    ["Tip: drag the minimap button to reposition it."] = "Astuce : faites glisser le bouton de la mini-carte pour le repositionner.",
    ["Font"] = "Police",
    ["Colors"] = "Couleurs",
    ["Count Color"] = "Couleur du compteur",
    ["Timer Color"] = "Couleur du minuteur",
    ["Click a color row to open the palette."] = "Cliquez sur une ligne de couleur pour ouvrir la palette.",
    ["Count Text"] = "Texte du compteur",
    ["Count Size"] = "Taille du compteur",
    ["Count X"] = "Compteur X",
    ["Count Y"] = "Compteur Y",
    ["Timer Text"] = "Texte du minuteur",
    ["Timer Size"] = "Taille du minuteur",
    ["Timer X"] = "Minuteur X",
    ["Timer Y"] = "Minuteur Y",
    ["Text auto-scales with icon size. Size sliders fine-tune that scaling."] = "Le texte se redimensionne automatiquement avec la taille de l’icône. Les curseurs permettent d’ajuster finement cette échelle.",
    ["Expiration Alerts"] = "Alertes d’expiration",
    ["Enable Expiration Alerts"] = "Activer les alertes d’expiration",
    ["Alert Threshold (seconds)"] = "Seuil d’alerte (secondes)",
    ["Alert Text Color"] = "Couleur du texte d’alerte",
    ["Glow Color"] = "Couleur de la lueur",
    ["WeakAura-Style Glow"] = "Lueur style WeakAura",
    ["Pulse Animation"] = "Animation pulsée",
    ["Sound options moved to the Sound tab for a cleaner layout."] = "Les options sonores ont été déplacées dans l’onglet Son pour une présentation plus claire.",
    ["Alert Sound"] = "Son d’alerte",
    ["Bell Toll Sound"] = "Son de cloche",
    ["Only Play Once Per Alert Window"] = "Ne jouer qu’une fois par fenêtre d’alerte",
    ["Repeat Every (seconds)"] = "Répéter toutes les (secondes)",
    ["Sound Channel"] = "Canal sonore",
    ["Master"] = "Principal",
    ["SFX"] = "Effets",
    ["Ambience"] = "Ambiance",
    ["Dialog"] = "Dialogue",
    ["Talking Head"] = "Bulle de dialogue",
    ["Uses Bell Toll. Test it below and pick the channel you want."] = "Utilise le son de cloche. Testez-le ci-dessous et choisissez le canal souhaité.",
    ["Test Sound"] = "Tester le son",
    ["Reset to Defaults"] = "Réinitialiser",
    ["Live Preview"] = "Aperçu en direct",
    ["Echo Preview"] = "Aperçu d’Echo",
    ["Large number: Echo count"] = "Grand nombre : nombre d’Echo",
    ["Small number: lowest Echo duration"] = "Petit nombre : durée d’Echo la plus basse",
    ["Updates as you change text, size, font, and color."] = "Se met à jour lorsque vous modifiez le texte, la taille, la police et la couleur.",
    ["Left Click: Open settings"] = "Clic gauche : ouvrir les paramètres",
    ["Drag: Move minimap button"] = "Faire glisser : déplacer le bouton de mini-carte",
    ["Right Click: Close settings"] = "Clic droit : fermer les paramètres",
    ["commands:"] = "commandes :",
    ["toggle settings"] = "afficher/masquer les paramètres",
    ["enable always show"] = "activer l’affichage permanent",
    ["disable always show"] = "désactiver l’affichage permanent",
    ["unlock tracker frame"] = "déverrouiller le cadre du tracker",
    ["lock tracker frame"] = "verrouiller le cadre du tracker",
    ["reset settings to defaults"] = "réinitialiser les paramètres",
    ["Alerts are configurable in the Alerts tab."] = "Les alertes sont configurables dans l’onglet Alertes.",
    ["Default"] = "Défaut",
  })
elseif locale == "esES" or locale == "esMX" then
  AddTranslations({
    ["Echo Tracker"] = "Echo Tracker",
    ["Drag window to move"] = "Arrastra la ventana para moverla",
    ["General"] = "General",
    ["Style"] = "Estilo",
    ["Text"] = "Texto",
    ["Alerts"] = "Alertas",
    ["Sound"] = "Sonido",
    ["Frame"] = "Marco",
    ["Icon Size"] = "Tamaño del icono",
    ["Unlock Frame"] = "Desbloquear marco",
    ["Lock Frame"] = "Bloquear marco",
    ["Always Show"] = "Mostrar siempre",
    ["Minimap"] = "Minimapa",
    ["Hide Minimap Button"] = "Ocultar botón del minimapa",
    ["Tip: drag the minimap button to reposition it."] = "Consejo: arrastra el botón del minimapa para recolocarlo.",
    ["Font"] = "Fuente",
    ["Colors"] = "Colores",
    ["Count Color"] = "Color del contador",
    ["Timer Color"] = "Color del temporizador",
    ["Click a color row to open the palette."] = "Haz clic en una fila de color para abrir la paleta.",
    ["Count Text"] = "Texto del contador",
    ["Count Size"] = "Tamaño del contador",
    ["Count X"] = "Contador X",
    ["Count Y"] = "Contador Y",
    ["Timer Text"] = "Texto del temporizador",
    ["Timer Size"] = "Tamaño del temporizador",
    ["Timer X"] = "Temporizador X",
    ["Timer Y"] = "Temporizador Y",
    ["Text auto-scales with icon size. Size sliders fine-tune that scaling."] = "El texto se escala automáticamente con el tamaño del icono. Los deslizadores ajustan ese escalado.",
    ["Expiration Alerts"] = "Alertas de expiración",
    ["Enable Expiration Alerts"] = "Activar alertas de expiración",
    ["Alert Threshold (seconds)"] = "Umbral de alerta (segundos)",
    ["Alert Text Color"] = "Color del texto de alerta",
    ["Glow Color"] = "Color del brillo",
    ["WeakAura-Style Glow"] = "Brillo estilo WeakAura",
    ["Pulse Animation"] = "Animación de pulso",
    ["Sound options moved to the Sound tab for a cleaner layout."] = "Las opciones de sonido se movieron a la pestaña Sonido para un diseño más limpio.",
    ["Alert Sound"] = "Sonido de alerta",
    ["Bell Toll Sound"] = "Sonido de campana",
    ["Only Play Once Per Alert Window"] = "Reproducir solo una vez por ventana de alerta",
    ["Repeat Every (seconds)"] = "Repetir cada (segundos)",
    ["Sound Channel"] = "Canal de sonido",
    ["Master"] = "Maestro",
    ["SFX"] = "Efectos",
    ["Ambience"] = "Ambiente",
    ["Dialog"] = "Diálogo",
    ["Talking Head"] = "Diálogo emergente",
    ["Uses Bell Toll. Test it below and pick the channel you want."] = "Usa sonido de campana. Pruébalo abajo y elige el canal que quieras.",
    ["Test Sound"] = "Probar sonido",
    ["Reset to Defaults"] = "Restablecer valores",
    ["Live Preview"] = "Vista previa",
    ["Echo Preview"] = "Vista previa de Echo",
    ["Large number: Echo count"] = "Número grande: cantidad de Echo",
    ["Small number: lowest Echo duration"] = "Número pequeño: menor duración de Echo",
    ["Updates as you change text, size, font, and color."] = "Se actualiza al cambiar texto, tamaño, fuente y color.",
    ["Left Click: Open settings"] = "Clic izquierdo: abrir ajustes",
    ["Drag: Move minimap button"] = "Arrastrar: mover botón del minimapa",
    ["Right Click: Close settings"] = "Clic derecho: cerrar ajustes",
    ["commands:"] = "comandos:",
    ["toggle settings"] = "mostrar u ocultar ajustes",
    ["enable always show"] = "activar mostrar siempre",
    ["disable always show"] = "desactivar mostrar siempre",
    ["unlock tracker frame"] = "desbloquear marco del rastreador",
    ["lock tracker frame"] = "bloquear marco del rastreador",
    ["reset settings to defaults"] = "restablecer ajustes",
    ["Alerts are configurable in the Alerts tab."] = "Las alertas se configuran en la pestaña Alertas.",
    ["Default"] = "Predeterminado",
  })
elseif locale == "itIT" then
  AddTranslations({
    ["Echo Tracker"] = "Echo Tracker",
    ["Drag window to move"] = "Trascina la finestra per spostarla",
    ["General"] = "Generale",
    ["Style"] = "Stile",
    ["Text"] = "Testo",
    ["Alerts"] = "Avvisi",
    ["Sound"] = "Suono",
    ["Frame"] = "Riquadro",
    ["Icon Size"] = "Dimensione icona",
    ["Unlock Frame"] = "Sblocca riquadro",
    ["Lock Frame"] = "Blocca riquadro",
    ["Always Show"] = "Mostra sempre",
    ["Minimap"] = "Minimappa",
    ["Hide Minimap Button"] = "Nascondi pulsante minimappa",
    ["Tip: drag the minimap button to reposition it."] = "Suggerimento: trascina il pulsante della minimappa per riposizionarlo.",
    ["Font"] = "Carattere",
    ["Colors"] = "Colori",
    ["Count Color"] = "Colore conteggio",
    ["Timer Color"] = "Colore timer",
    ["Click a color row to open the palette."] = "Clicca una riga colore per aprire la tavolozza.",
    ["Count Text"] = "Testo conteggio",
    ["Count Size"] = "Dimensione conteggio",
    ["Count X"] = "Conteggio X",
    ["Count Y"] = "Conteggio Y",
    ["Timer Text"] = "Testo timer",
    ["Timer Size"] = "Dimensione timer",
    ["Timer X"] = "Timer X",
    ["Timer Y"] = "Timer Y",
    ["Text auto-scales with icon size. Size sliders fine-tune that scaling."] = "Il testo si ridimensiona automaticamente con la dimensione dell’icona. I cursori regolano con precisione questa scala.",
    ["Expiration Alerts"] = "Avvisi di scadenza",
    ["Enable Expiration Alerts"] = "Abilita avvisi di scadenza",
    ["Alert Threshold (seconds)"] = "Soglia avviso (secondi)",
    ["Alert Text Color"] = "Colore testo avviso",
    ["Glow Color"] = "Colore bagliore",
    ["WeakAura-Style Glow"] = "Bagliore stile WeakAura",
    ["Pulse Animation"] = "Animazione impulso",
    ["Sound options moved to the Sound tab for a cleaner layout."] = "Le opzioni audio sono state spostate nella scheda Suono per un layout più pulito.",
    ["Alert Sound"] = "Suono avviso",
    ["Bell Toll Sound"] = "Suono campana",
    ["Only Play Once Per Alert Window"] = "Riproduci solo una volta per finestra di avviso",
    ["Repeat Every (seconds)"] = "Ripeti ogni (secondi)",
    ["Sound Channel"] = "Canale audio",
    ["Master"] = "Master",
    ["SFX"] = "Effetti",
    ["Ambience"] = "Ambiente",
    ["Dialog"] = "Dialogo",
    ["Talking Head"] = "Talking Head",
    ["Uses Bell Toll. Test it below and pick the channel you want."] = "Usa il suono campana. Provalo qui sotto e scegli il canale desiderato.",
    ["Test Sound"] = "Testa suono",
    ["Reset to Defaults"] = "Ripristina predefiniti",
    ["Live Preview"] = "Anteprima live",
    ["Echo Preview"] = "Anteprima Echo",
    ["Large number: Echo count"] = "Numero grande: conteggio Echo",
    ["Small number: lowest Echo duration"] = "Numero piccolo: durata Echo più bassa",
    ["Updates as you change text, size, font, and color."] = "Si aggiorna quando cambi testo, dimensione, carattere e colore.",
    ["Left Click: Open settings"] = "Click sinistro: apri impostazioni",
    ["Drag: Move minimap button"] = "Trascina: sposta pulsante minimappa",
    ["Right Click: Close settings"] = "Click destro: chiudi impostazioni",
    ["commands:"] = "comandi:",
    ["toggle settings"] = "mostra/nascondi impostazioni",
    ["enable always show"] = "attiva mostra sempre",
    ["disable always show"] = "disattiva mostra sempre",
    ["unlock tracker frame"] = "sblocca riquadro tracker",
    ["lock tracker frame"] = "blocca riquadro tracker",
    ["reset settings to defaults"] = "ripristina impostazioni",
    ["Alerts are configurable in the Alerts tab."] = "Gli avvisi sono configurabili nella scheda Avvisi.",
    ["Default"] = "Predefinito",
  })
elseif locale == "ptBR" then
  AddTranslations({
    ["Echo Tracker"] = "Echo Tracker",
    ["Drag window to move"] = "Arraste a janela para mover",
    ["General"] = "Geral",
    ["Style"] = "Estilo",
    ["Text"] = "Texto",
    ["Alerts"] = "Alertas",
    ["Sound"] = "Som",
    ["Frame"] = "Janela",
    ["Icon Size"] = "Tamanho do ícone",
    ["Unlock Frame"] = "Destravar janela",
    ["Lock Frame"] = "Travar janela",
    ["Always Show"] = "Sempre mostrar",
    ["Minimap"] = "Minimapa",
    ["Hide Minimap Button"] = "Ocultar botão do minimapa",
    ["Tip: drag the minimap button to reposition it."] = "Dica: arraste o botão do minimapa para reposicioná-lo.",
    ["Font"] = "Fonte",
    ["Colors"] = "Cores",
    ["Count Color"] = "Cor da contagem",
    ["Timer Color"] = "Cor do temporizador",
    ["Click a color row to open the palette."] = "Clique em uma linha de cor para abrir a paleta.",
    ["Count Text"] = "Texto da contagem",
    ["Count Size"] = "Tamanho da contagem",
    ["Count X"] = "Contagem X",
    ["Count Y"] = "Contagem Y",
    ["Timer Text"] = "Texto do temporizador",
    ["Timer Size"] = "Tamanho do temporizador",
    ["Timer X"] = "Temporizador X",
    ["Timer Y"] = "Temporizador Y",
    ["Text auto-scales with icon size. Size sliders fine-tune that scaling."] = "O texto escala automaticamente com o tamanho do ícone. Os controles ajustam esse tamanho com precisão.",
    ["Expiration Alerts"] = "Alertas de expiração",
    ["Enable Expiration Alerts"] = "Ativar alertas de expiração",
    ["Alert Threshold (seconds)"] = "Limite do alerta (segundos)",
    ["Alert Text Color"] = "Cor do texto do alerta",
    ["Glow Color"] = "Cor do brilho",
    ["WeakAura-Style Glow"] = "Brilho estilo WeakAura",
    ["Pulse Animation"] = "Animação de pulso",
    ["Sound options moved to the Sound tab for a cleaner layout."] = "As opções de som foram movidas para a aba Som para um layout mais limpo.",
    ["Alert Sound"] = "Som de alerta",
    ["Bell Toll Sound"] = "Som de sino",
    ["Only Play Once Per Alert Window"] = "Tocar apenas uma vez por janela de alerta",
    ["Repeat Every (seconds)"] = "Repetir a cada (segundos)",
    ["Sound Channel"] = "Canal de som",
    ["Master"] = "Master",
    ["SFX"] = "Efeitos",
    ["Ambience"] = "Ambiente",
    ["Dialog"] = "Diálogo",
    ["Talking Head"] = "Talking Head",
    ["Uses Bell Toll. Test it below and pick the channel you want."] = "Usa sino. Teste abaixo e escolha o canal desejado.",
    ["Test Sound"] = "Testar som",
    ["Reset to Defaults"] = "Restaurar padrão",
    ["Live Preview"] = "Prévia ao vivo",
    ["Echo Preview"] = "Prévia do Echo",
    ["Large number: Echo count"] = "Número grande: quantidade de Echo",
    ["Small number: lowest Echo duration"] = "Número pequeno: menor duração de Echo",
    ["Updates as you change text, size, font, and color."] = "Atualiza conforme você muda texto, tamanho, fonte e cor.",
    ["Left Click: Open settings"] = "Clique esquerdo: abrir configurações",
    ["Drag: Move minimap button"] = "Arrastar: mover botão do minimapa",
    ["Right Click: Close settings"] = "Clique direito: fechar configurações",
    ["commands:"] = "comandos:",
    ["toggle settings"] = "alternar configurações",
    ["enable always show"] = "ativar sempre mostrar",
    ["disable always show"] = "desativar sempre mostrar",
    ["unlock tracker frame"] = "destravar janela do rastreador",
    ["lock tracker frame"] = "travar janela do rastreador",
    ["reset settings to defaults"] = "restaurar configurações",
    ["Alerts are configurable in the Alerts tab."] = "Os alertas podem ser configurados na aba Alertas.",
    ["Default"] = "Padrão",
  })
elseif locale == "ruRU" then
  AddTranslations({
    ["Echo Tracker"] = "Echo Tracker",
    ["Drag window to move"] = "Перетащите окно, чтобы переместить его",
    ["General"] = "Общие",
    ["Style"] = "Стиль",
    ["Text"] = "Текст",
    ["Alerts"] = "Оповещения",
    ["Sound"] = "Звук",
    ["Frame"] = "Рамка",
    ["Icon Size"] = "Размер иконки",
    ["Unlock Frame"] = "Разблокировать рамку",
    ["Lock Frame"] = "Заблокировать рамку",
    ["Always Show"] = "Показывать всегда",
    ["Minimap"] = "Миникарта",
    ["Hide Minimap Button"] = "Скрыть кнопку у миникарты",
    ["Tip: drag the minimap button to reposition it."] = "Подсказка: перетащите кнопку у миникарты, чтобы изменить её положение.",
    ["Font"] = "Шрифт",
    ["Colors"] = "Цвета",
    ["Count Color"] = "Цвет счётчика",
    ["Timer Color"] = "Цвет таймера",
    ["Click a color row to open the palette."] = "Нажмите на строку цвета, чтобы открыть палитру.",
    ["Count Text"] = "Текст счётчика",
    ["Count Size"] = "Размер счётчика",
    ["Count X"] = "Счётчик X",
    ["Count Y"] = "Счётчик Y",
    ["Timer Text"] = "Текст таймера",
    ["Timer Size"] = "Размер таймера",
    ["Timer X"] = "Таймер X",
    ["Timer Y"] = "Таймер Y",
    ["Text auto-scales with icon size. Size sliders fine-tune that scaling."] = "Текст автоматически масштабируется вместе с размером иконки. Ползунки позволяют точно настроить это масштабирование.",
    ["Expiration Alerts"] = "Оповещения об окончании",
    ["Enable Expiration Alerts"] = "Включить оповещения об окончании",
    ["Alert Threshold (seconds)"] = "Порог оповещения (секунды)",
    ["Alert Text Color"] = "Цвет текста оповещения",
    ["Glow Color"] = "Цвет свечения",
    ["WeakAura-Style Glow"] = "Свечение в стиле WeakAura",
    ["Pulse Animation"] = "Пульсация",
    ["Sound options moved to the Sound tab for a cleaner layout."] = "Параметры звука перенесены на вкладку «Звук» для более чистого интерфейса.",
    ["Alert Sound"] = "Звук оповещения",
    ["Bell Toll Sound"] = "Звук колокола",
    ["Only Play Once Per Alert Window"] = "Проигрывать только один раз за окно оповещения",
    ["Repeat Every (seconds)"] = "Повторять каждые (секунды)",
    ["Sound Channel"] = "Канал звука",
    ["Master"] = "Общий",
    ["SFX"] = "Эффекты",
    ["Ambience"] = "Окружение",
    ["Dialog"] = "Диалог",
    ["Talking Head"] = "Talking Head",
    ["Uses Bell Toll. Test it below and pick the channel you want."] = "Использует звук колокола. Проверьте его ниже и выберите нужный канал.",
    ["Test Sound"] = "Проверить звук",
    ["Reset to Defaults"] = "Сбросить настройки",
    ["Live Preview"] = "Предпросмотр",
    ["Echo Preview"] = "Предпросмотр Echo",
    ["Large number: Echo count"] = "Большое число: количество Echo",
    ["Small number: lowest Echo duration"] = "Малое число: минимальная длительность Echo",
    ["Updates as you change text, size, font, and color."] = "Обновляется при изменении текста, размера, шрифта и цвета.",
    ["Left Click: Open settings"] = "ЛКМ: открыть настройки",
    ["Drag: Move minimap button"] = "Перетащить: переместить кнопку миникарты",
    ["Right Click: Close settings"] = "ПКМ: закрыть настройки",
    ["commands:"] = "команды:",
    ["toggle settings"] = "открыть или закрыть настройки",
    ["enable always show"] = "включить постоянный показ",
    ["disable always show"] = "выключить постоянный показ",
    ["unlock tracker frame"] = "разблокировать рамку трекера",
    ["lock tracker frame"] = "заблокировать рамку трекера",
    ["reset settings to defaults"] = "сбросить настройки",
    ["Alerts are configurable in the Alerts tab."] = "Оповещения настраиваются на вкладке «Оповещения».",
    ["Default"] = "По умолчанию",
  })
elseif locale == "koKR" then
  AddTranslations({
    ["Echo Tracker"] = "Echo Tracker",
    ["Drag window to move"] = "창을 드래그해 이동합니다",
    ["General"] = "일반",
    ["Style"] = "스타일",
    ["Text"] = "텍스트",
    ["Alerts"] = "경고",
    ["Sound"] = "소리",
    ["Frame"] = "프레임",
    ["Icon Size"] = "아이콘 크기",
    ["Unlock Frame"] = "프레임 잠금 해제",
    ["Lock Frame"] = "프레임 잠금",
    ["Always Show"] = "항상 표시",
    ["Minimap"] = "미니맵",
    ["Hide Minimap Button"] = "미니맵 버튼 숨기기",
    ["Tip: drag the minimap button to reposition it."] = "팁: 미니맵 버튼을 드래그해 위치를 바꾸세요.",
    ["Font"] = "글꼴",
    ["Colors"] = "색상",
    ["Count Color"] = "카운트 색상",
    ["Timer Color"] = "타이머 색상",
    ["Click a color row to open the palette."] = "색상 행을 클릭해 팔레트를 여세요.",
    ["Count Text"] = "카운트 텍스트",
    ["Count Size"] = "카운트 크기",
    ["Count X"] = "카운트 X",
    ["Count Y"] = "카운트 Y",
    ["Timer Text"] = "타이머 텍스트",
    ["Timer Size"] = "타이머 크기",
    ["Timer X"] = "타이머 X",
    ["Timer Y"] = "타이머 Y",
    ["Text auto-scales with icon size. Size sliders fine-tune that scaling."] = "텍스트는 아이콘 크기에 맞춰 자동으로 조정됩니다. 슬라이더로 세밀하게 조절할 수 있습니다.",
    ["Expiration Alerts"] = "만료 경고",
    ["Enable Expiration Alerts"] = "만료 경고 사용",
    ["Alert Threshold (seconds)"] = "경고 기준값(초)",
    ["Alert Text Color"] = "경고 텍스트 색상",
    ["Glow Color"] = "광채 색상",
    ["WeakAura-Style Glow"] = "WeakAura 스타일 광채",
    ["Pulse Animation"] = "펄스 애니메이션",
    ["Sound options moved to the Sound tab for a cleaner layout."] = "더 깔끔한 구성을 위해 소리 옵션을 소리 탭으로 옮겼습니다.",
    ["Alert Sound"] = "경고 소리",
    ["Bell Toll Sound"] = "종소리",
    ["Only Play Once Per Alert Window"] = "경고 구간당 한 번만 재생",
    ["Repeat Every (seconds)"] = "반복 간격(초)",
    ["Sound Channel"] = "소리 채널",
    ["Master"] = "마스터",
    ["SFX"] = "효과음",
    ["Ambience"] = "환경음",
    ["Dialog"] = "대화",
    ["Talking Head"] = "말머리",
    ["Uses Bell Toll. Test it below and pick the channel you want."] = "종소리를 사용합니다. 아래에서 시험하고 원하는 채널을 고르세요.",
    ["Test Sound"] = "소리 테스트",
    ["Reset to Defaults"] = "기본값으로 초기화",
    ["Live Preview"] = "실시간 미리보기",
    ["Echo Preview"] = "Echo 미리보기",
    ["Large number: Echo count"] = "큰 숫자: Echo 개수",
    ["Small number: lowest Echo duration"] = "작은 숫자: 가장 짧은 Echo 지속시간",
    ["Updates as you change text, size, font, and color."] = "텍스트, 크기, 글꼴, 색상을 바꾸면 바로 반영됩니다.",
    ["Left Click: Open settings"] = "좌클릭: 설정 열기",
    ["Drag: Move minimap button"] = "드래그: 미니맵 버튼 이동",
    ["Right Click: Close settings"] = "우클릭: 설정 닫기",
    ["commands:"] = "명령어:",
    ["toggle settings"] = "설정 열기/닫기",
    ["enable always show"] = "항상 표시 켜기",
    ["disable always show"] = "항상 표시 끄기",
    ["unlock tracker frame"] = "트래커 프레임 잠금 해제",
    ["lock tracker frame"] = "트래커 프레임 잠금",
    ["reset settings to defaults"] = "설정 초기화",
    ["Alerts are configurable in the Alerts tab."] = "경고는 경고 탭에서 설정할 수 있습니다.",
    ["Default"] = "기본값",
  })
elseif locale == "zhCN" then
  AddTranslations({
    ["Echo Tracker"] = "Echo Tracker",
    ["Drag window to move"] = "拖动窗口进行移动",
    ["General"] = "常规",
    ["Style"] = "样式",
    ["Text"] = "文本",
    ["Alerts"] = "警报",
    ["Sound"] = "声音",
    ["Frame"] = "框体",
    ["Icon Size"] = "图标大小",
    ["Unlock Frame"] = "解锁框体",
    ["Lock Frame"] = "锁定框体",
    ["Always Show"] = "始终显示",
    ["Minimap"] = "小地图",
    ["Hide Minimap Button"] = "隐藏小地图按钮",
    ["Tip: drag the minimap button to reposition it."] = "提示：拖动小地图按钮来重新定位。",
    ["Font"] = "字体",
    ["Colors"] = "颜色",
    ["Count Color"] = "计数颜色",
    ["Timer Color"] = "计时颜色",
    ["Click a color row to open the palette."] = "点击颜色行以打开调色板。",
    ["Count Text"] = "计数文本",
    ["Count Size"] = "计数大小",
    ["Count X"] = "计数 X",
    ["Count Y"] = "计数 Y",
    ["Timer Text"] = "计时文本",
    ["Timer Size"] = "计时大小",
    ["Timer X"] = "计时 X",
    ["Timer Y"] = "计时 Y",
    ["Text auto-scales with icon size. Size sliders fine-tune that scaling."] = "文本会随图标大小自动缩放，滑块可进一步微调。",
    ["Expiration Alerts"] = "到期警报",
    ["Enable Expiration Alerts"] = "启用到期警报",
    ["Alert Threshold (seconds)"] = "警报阈值（秒）",
    ["Alert Text Color"] = "警报文字颜色",
    ["Glow Color"] = "发光颜色",
    ["WeakAura-Style Glow"] = "WeakAura 风格发光",
    ["Pulse Animation"] = "脉冲动画",
    ["Sound options moved to the Sound tab for a cleaner layout."] = "声音选项已移到“声音”标签页，以获得更简洁的布局。",
    ["Alert Sound"] = "警报声音",
    ["Bell Toll Sound"] = "钟声",
    ["Only Play Once Per Alert Window"] = "每次警报窗口仅播放一次",
    ["Repeat Every (seconds)"] = "重复间隔（秒）",
    ["Sound Channel"] = "声音频道",
    ["Master"] = "主音量",
    ["SFX"] = "音效",
    ["Ambience"] = "环境音",
    ["Dialog"] = "对话",
    ["Talking Head"] = "说话头像",
    ["Uses Bell Toll. Test it below and pick the channel you want."] = "使用钟声。可在下方测试并选择所需频道。",
    ["Test Sound"] = "测试声音",
    ["Reset to Defaults"] = "恢复默认",
    ["Live Preview"] = "实时预览",
    ["Echo Preview"] = "Echo 预览",
    ["Large number: Echo count"] = "大数字：Echo 数量",
    ["Small number: lowest Echo duration"] = "小数字：最低 Echo 持续时间",
    ["Updates as you change text, size, font, and color."] = "更改文本、大小、字体和颜色时会即时更新。",
    ["Left Click: Open settings"] = "左键：打开设置",
    ["Drag: Move minimap button"] = "拖动：移动小地图按钮",
    ["Right Click: Close settings"] = "右键：关闭设置",
    ["commands:"] = "命令：",
    ["toggle settings"] = "切换设置",
    ["enable always show"] = "启用始终显示",
    ["disable always show"] = "禁用始终显示",
    ["unlock tracker frame"] = "解锁追踪框体",
    ["lock tracker frame"] = "锁定追踪框体",
    ["reset settings to defaults"] = "重置设置",
    ["Alerts are configurable in the Alerts tab."] = "警报可在“警报”标签页中配置。",
    ["Enable Radial Timer"] = "启用环形计时",
    ["Radial Opacity"] = "环形不透明度",
    ["Fade Radial With Timer"] = "环形随剩余时间淡出",
    ["show spell table self-check"] = "显示法术表自检",
    ["unknown spell"] = "未知法术",
    ["Echo duration"] = "Echo 持续时间",
    ["calibrated"] = "已校准",
    ["not yet calibrated"] = "尚未校准",
    ["Applies Echo"] = "施加 Echo 的法术",
    ["Consumes Echo"] = "消耗 Echo 的法术",
    ["friendly target only"] = "仅友方目标",
    ["Also show count outside raids"] = "在团队副本外也显示计数",
    ["Outside raids Temporal Anomaly often hits fewer than 5, so the count reads high."] = "团队副本外时间异常常常打不满 5 个，计数会偏高。",
    ["empowered, settled on release"] = "蓄力法术，松手才结算",
    ["Grants an extra Echo target"] = "使下一个 Echo 多一个目标",
    ["stacks max"] = "层上限",
    ["Default"] = "默认",
    ["Open Settings"] = "打开设置",
    ["Settings open in their own movable window, so you can drag them aside and watch the tracker update as you make changes."] = "设置会在独立的可拖动窗口中打开，你可以把它拖到一边，边调边看追踪器的实时变化。",
    ["same as /sce, if you prefer the full name"] = "与 /sce 等价，喜欢完整命令的话可以用它",
    ["Also reachable from ESC > Options > AddOns."] = "也可以从 ESC > 选项 > 插件 中打开。",
  })
elseif locale == "zhTW" then
  AddTranslations({
    ["Echo Tracker"] = "Echo Tracker",
    ["Drag window to move"] = "拖曳視窗來移動",
    ["General"] = "一般",
    ["Style"] = "樣式",
    ["Text"] = "文字",
    ["Alerts"] = "警示",
    ["Sound"] = "聲音",
    ["Frame"] = "框架",
    ["Icon Size"] = "圖示大小",
    ["Unlock Frame"] = "解除鎖定框架",
    ["Lock Frame"] = "鎖定框架",
    ["Always Show"] = "永遠顯示",
    ["Minimap"] = "小地圖",
    ["Hide Minimap Button"] = "隱藏小地圖按鈕",
    ["Tip: drag the minimap button to reposition it."] = "提示：拖曳小地圖按鈕來重新定位。",
    ["Font"] = "字型",
    ["Colors"] = "顏色",
    ["Count Color"] = "計數顏色",
    ["Timer Color"] = "計時顏色",
    ["Click a color row to open the palette."] = "點擊顏色列以開啟調色盤。",
    ["Count Text"] = "計數文字",
    ["Count Size"] = "計數大小",
    ["Count X"] = "計數 X",
    ["Count Y"] = "計數 Y",
    ["Timer Text"] = "計時文字",
    ["Timer Size"] = "計時大小",
    ["Timer X"] = "計時 X",
    ["Timer Y"] = "計時 Y",
    ["Text auto-scales with icon size. Size sliders fine-tune that scaling."] = "文字會隨圖示大小自動縮放，滑桿可進一步微調。",
    ["Expiration Alerts"] = "到期警示",
    ["Enable Expiration Alerts"] = "啟用到期警示",
    ["Alert Threshold (seconds)"] = "警示門檻（秒）",
    ["Alert Text Color"] = "警示文字顏色",
    ["Glow Color"] = "發光顏色",
    ["WeakAura-Style Glow"] = "WeakAura 風格發光",
    ["Pulse Animation"] = "脈衝動畫",
    ["Sound options moved to the Sound tab for a cleaner layout."] = "聲音選項已移至「聲音」分頁，以提供更整潔的版面。",
    ["Alert Sound"] = "警示聲音",
    ["Bell Toll Sound"] = "鐘聲",
    ["Only Play Once Per Alert Window"] = "每個警示視窗只播放一次",
    ["Repeat Every (seconds)"] = "重複間隔（秒）",
    ["Sound Channel"] = "聲音頻道",
    ["Master"] = "主音量",
    ["SFX"] = "音效",
    ["Ambience"] = "環境",
    ["Dialog"] = "對話",
    ["Talking Head"] = "對話頭像",
    ["Uses Bell Toll. Test it below and pick the channel you want."] = "使用鐘聲。可在下方測試並選擇你要的頻道。",
    ["Test Sound"] = "測試聲音",
    ["Reset to Defaults"] = "重設為預設值",
    ["Live Preview"] = "即時預覽",
    ["Echo Preview"] = "Echo 預覽",
    ["Large number: Echo count"] = "大數字：Echo 數量",
    ["Small number: lowest Echo duration"] = "小數字：最低 Echo 持續時間",
    ["Updates as you change text, size, font, and color."] = "變更文字、大小、字型與顏色時會即時更新。",
    ["Left Click: Open settings"] = "左鍵：開啟設定",
    ["Drag: Move minimap button"] = "拖曳：移動小地圖按鈕",
    ["Right Click: Close settings"] = "右鍵：關閉設定",
    ["commands:"] = "指令：",
    ["toggle settings"] = "切換設定",
    ["enable always show"] = "啟用永遠顯示",
    ["disable always show"] = "停用永遠顯示",
    ["unlock tracker frame"] = "解除鎖定追蹤框架",
    ["lock tracker frame"] = "鎖定追蹤框架",
    ["reset settings to defaults"] = "重設設定",
    ["Alerts are configurable in the Alerts tab."] = "警示可在「警示」分頁中設定。",
    ["Enable Radial Timer"] = "啟用環形計時",
    ["Radial Opacity"] = "環形不透明度",
    ["Fade Radial With Timer"] = "環形隨剩餘時間淡出",
    ["show spell table self-check"] = "顯示法術表自檢",
    ["unknown spell"] = "未知法術",
    ["Echo duration"] = "Echo 持續時間",
    ["calibrated"] = "已校準",
    ["not yet calibrated"] = "尚未校準",
    ["Applies Echo"] = "施加 Echo 的法術",
    ["Consumes Echo"] = "消耗 Echo 的法術",
    ["friendly target only"] = "僅友方目標",
    ["Also show count outside raids"] = "在團隊副本外也顯示計數",
    ["Outside raids Temporal Anomaly often hits fewer than 5, so the count reads high."] = "團隊副本外時間異常常常打不滿 5 個，計數會偏高。",
    ["empowered, settled on release"] = "蓄力法術，鬆手才結算",
    ["Grants an extra Echo target"] = "使下一個 Echo 多一個目標",
    ["stacks max"] = "層上限",
    ["Default"] = "預設",
    ["Open Settings"] = "開啟設定",
    ["Settings open in their own movable window, so you can drag them aside and watch the tracker update as you make changes."] = "設定會在獨立的可拖曳視窗中開啟，你可以把它拖到一邊，邊調邊看追蹤器的即時變化。",
    ["same as /sce, if you prefer the full name"] = "與 /sce 等價，喜歡完整指令的話可以用它",
    ["Also reachable from ESC > Options > AddOns."] = "也可以從 ESC > 選項 > 插件 中開啟。",
  })
end

setmetatable(L, {
  __index = function(_, key)
    return key
  end
})

local function GetSoundChannelLabel(value)
  if value == "TalkingHead" or value == "Talking Head" then
    return L["Talking Head"]
  end
  return L[value or "Master"]
end


local FONT_OPTIONS = {
  { text = L["Default"], value = STANDARD_TEXT_FONT },
  { text = "Friz Quadrata", value = GameFontNormal:GetFont() },
  { text = "Arial Narrow", value = "Fonts\\ARIALN.TTF" },
  { text = "Morpheus", value = "Fonts\\MORPHEUS.TTF" },
  { text = "Skurri", value = "Fonts\\SKURRI.TTF" },
}

local defaults = {
  point = "CENTER",
  relativePoint = "CENTER",
  x = 0,
  y = 0,

  frameSize = 64,

  countSizeAdjust = 0,
  countColor = { 1, 1, 1 },
  countOffsetX = 0,
  countOffsetY = 0,
  countOutsideRaid = false,

  timerSizeAdjust = 0,
  timerColor = { 1, 1, 1 },
  timerOffsetX = -3,
  timerOffsetY = 3,

  fontPath = STANDARD_TEXT_FONT,

  radialOpacity = 50,

  unlocked = false,
  alwaysShow = false,
  lastTab = "general",
  showPreview = true,

  panelPoint = "CENTER",
  panelRelativePoint = "CENTER",
  panelX = 0,
  panelY = 0,

  minimap = {
    hide = false,
    angle = 220,
    radius = 106,
  },

  alerts = {
    enabled = true,
    threshold = 3,
    textColor = { 1, 0.18, 0.18 },
    glowColor = { 1, 0.36, 0.36 },
    glow = true,
    pulse = true,
    sound = true,
    soundChannel = "Master",
    oncePerCast = true,
    repeatSeconds = 1,
  },
}

local PANEL_WIDTH = 620
local PANEL_HEIGHT = 560

local NAV_LEFT = 18
local NAV_TOP = -74
local NAV_WIDTH = 110
local NAV_BUTTON_HEIGHT = 34
local NAV_BUTTON_GAP = 8

local CONTENT_LEFT = 150
local CONTENT_TOP = -76
local CONTENT_RIGHT = -150
local CONTENT_BOTTOM = 28

local frame
local panel
local minimapButton
local unlockButton
local pages = {}
local tabButtons = {}
local styleWidgets = {}
local controls = {}
local panelPreview = {}
local alertState = {
  active = false,
  soundPlayed = false,
  repeatTimer = 0,
}
local ALERT_SOUND_ID = 6595

local function CopyDefaults(src, dst)
  if type(dst) ~= "table" then
    dst = {}
  end

  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = CopyDefaults(v, dst[k])
    elseif dst[k] == nil then
      dst[k] = v
    end
  end

  return dst
end

SeaCatEchoTrackerDB = CopyDefaults(defaults, SeaCatEchoTrackerDB)
SeaCatEchoTrackerDB.minimap = CopyDefaults(defaults.minimap, SeaCatEchoTrackerDB.minimap)
SeaCatEchoTrackerDB.showPreview = true

local function EnsureAlertSettings()
  SeaCatEchoTrackerDB = SeaCatEchoTrackerDB or {}
  SeaCatEchoTrackerDB.alerts = CopyDefaults(defaults.alerts, SeaCatEchoTrackerDB.alerts)

  local alerts = SeaCatEchoTrackerDB.alerts

  if alerts.color and not alerts.textColor then
    alerts.textColor = CopyDefaults(defaults.alerts.textColor, alerts.color)
  end
  if alerts.color then
    alerts.color = nil
  end

  alerts.textColor = CopyDefaults(defaults.alerts.textColor, alerts.textColor)
  alerts.glowColor = CopyDefaults(defaults.alerts.glowColor, alerts.glowColor)

  if alerts.soundChannel ~= "Master" and alerts.soundChannel ~= "SFX" and alerts.soundChannel ~= "Ambience" and alerts.soundChannel ~= "Dialog" and alerts.soundChannel ~= "Talking Head" and alerts.soundChannel ~= "TalkingHead" then
    alerts.soundChannel = defaults.alerts.soundChannel
  end

  if alerts.soundChannel == "Talking Head" then
    alerts.soundChannel = "TalkingHead"
  end

  if alerts.oncePerCast == nil then
    alerts.oncePerCast = defaults.alerts.oncePerCast
  end

  if type(alerts.repeatSeconds) ~= "number" or alerts.repeatSeconds <= 0 then
    alerts.repeatSeconds = defaults.alerts.repeatSeconds
  end

  return alerts
end

EnsureAlertSettings()

local function SafeSetFont(fontString, fontPath, size, flags)
  if not fontString then
    return
  end

  local resolvedFont = fontPath

  if type(resolvedFont) == "function" then
    resolvedFont = resolvedFont()
  end

  if type(resolvedFont) ~= "string" or resolvedFont == "" then
    resolvedFont = STANDARD_TEXT_FONT
  end

  local ok = fontString:SetFont(resolvedFont, size, flags)
  if not ok then
    fontString:SetFont(STANDARD_TEXT_FONT, size, flags)
    SeaCatEchoTrackerDB.fontPath = STANDARD_TEXT_FONT
  end
end

local function GetAutoTextSizes(size)
  local countSize = math.max(12, math.floor((size * 0.4375) + 0.5) + (SeaCatEchoTrackerDB.countSizeAdjust or 0))
  local timerSize = math.max(8, math.floor((size * 0.21875) + 0.5) + (SeaCatEchoTrackerDB.timerSizeAdjust or 0))
  return countSize, timerSize
end

local function AlertIsEnabled()
  local alerts = EnsureAlertSettings()
  return alerts.enabled
end

local function GetAlertTextColor()
  local alertColor = EnsureAlertSettings().textColor
  return alertColor[1], alertColor[2], alertColor[3]
end

local function GetAlertGlowColor()
  local glowColor = EnsureAlertSettings().glowColor
  return glowColor[1], glowColor[2], glowColor[3]
end

local function CreateSoftGlowContainer(parent, anchor)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetFrameLevel(parent:GetFrameLevel() + 3)
  holder:SetPoint("TOPLEFT", anchor, "TOPLEFT", -6, 6)
  holder:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 6, -6)
  holder:Hide()

  holder.edges = {}
  holder.corners = {}

  local function NewTex(target)
    local tex = holder:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    tex:SetBlendMode("ADD")
    tex:SetVertexColor(1, 0.36, 0.36, 0.55)
    table.insert(target, tex)
    return tex
  end

  local top = NewTex(holder.edges)
  top:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, 0)
  top:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -4, 0)
  top:SetHeight(3)

  local bottom = NewTex(holder.edges)
  bottom:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 4, 0)
  bottom:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -4, 0)
  bottom:SetHeight(3)

  local left = NewTex(holder.edges)
  left:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -4)
  left:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 4)
  left:SetWidth(3)

  local right = NewTex(holder.edges)
  right:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -4)
  right:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 4)
  right:SetWidth(3)

  local tl = NewTex(holder.corners)
  tl:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  tl:SetSize(6, 6)

  local tr = NewTex(holder.corners)
  tr:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
  tr:SetSize(6, 6)

  local bl = NewTex(holder.corners)
  bl:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
  bl:SetSize(6, 6)

  local br = NewTex(holder.corners)
  br:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
  br:SetSize(6, 6)

  return holder
end

local function SetGlowContainerColor(glowContainer, r, g, b, edgeAlpha, cornerAlpha)
  if not glowContainer then
    return
  end

  edgeAlpha = edgeAlpha or 0.60
  cornerAlpha = cornerAlpha or 0.80

  if glowContainer.edges then
    for _, tex in ipairs(glowContainer.edges) do
      tex:SetVertexColor(r, g, b, edgeAlpha)
    end
  end

  if glowContainer.corners then
    for _, tex in ipairs(glowContainer.corners) do
      tex:SetVertexColor(r, g, b, cornerAlpha)
    end
  end
end

local function EnsurePulseAnimation(target)
  if not target or target.echoTrackerPulse then
    return
  end

  local pulseScale = 1.035

  local group = target:CreateAnimationGroup()
  group:SetLooping("REPEAT")

  local scaleUp = group:CreateAnimation("Scale")
  scaleUp:SetOrder(1)
  scaleUp:SetDuration(0.42)
  scaleUp:SetScale(pulseScale, pulseScale)

  local scaleDown = group:CreateAnimation("Scale")
  scaleDown:SetOrder(2)
  scaleDown:SetDuration(0.42)
  scaleDown:SetScale(1 / pulseScale, 1 / pulseScale)

  target.echoTrackerPulse = group
end

local function SetAlertVisualState(active)
  if not frame then
    return
  end

  local showGlow = active and AlertIsEnabled() and SeaCatEchoTrackerDB.alerts.glow
  local showPulse = active and AlertIsEnabled() and SeaCatEchoTrackerDB.alerts.pulse

  if frame.alertGlow then
    if showGlow then
      frame.alertGlow:Show()
    else
      frame.alertGlow:Hide()
    end
  end

  if frame.echoTrackerPulse then
    if showPulse then
      if not frame.echoTrackerPulse:IsPlaying() then
        frame.echoTrackerPulse:Play()
      end
    else
      frame.echoTrackerPulse:Stop()
      frame:SetScale(1)
    end
  end

  if panelPreview.frame and panelPreview.frame.echoTrackerPulse then
    panelPreview.frame.echoTrackerPulse:Stop()
    panelPreview.frame:SetScale(1)
  end
end

local function UpdateAlertVisualColor()
  local glowR, glowG, glowB = GetAlertGlowColor()

  if frame and frame.alertGlow then
    SetGlowContainerColor(frame.alertGlow, glowR, glowG, glowB, 0.60, 0.82)
  end

  if panelPreview.alertGlow then
    SetGlowContainerColor(panelPreview.alertGlow, glowR, glowG, glowB, 0.60, 0.82)
  end
end

local function PlayAlertSound()
  local alerts = EnsureAlertSettings()
  if not AlertIsEnabled() or not alerts.sound then
    return
  end

  local channel = alerts.soundChannel or "Master"
  if channel == "Talking Head" then
    channel = "TalkingHead"
  end

  local ok = false
  if PlaySound then
    ok = PlaySound(ALERT_SOUND_ID, channel) and true or false
  end
  if not ok and PlaySoundFile then
    ok = PlaySoundFile(567463, channel) and true or false
  end
  if not ok and PlaySound then
    PlaySound(SOUNDKIT.READY_CHECK, channel)
  end
end

local function UpdateAlertState(active, elapsed)
  local alerts = EnsureAlertSettings()

  if not active then
    alertState.active = false
    alertState.soundPlayed = false
    alertState.repeatTimer = 0
    SetAlertVisualState(false)
    return
  end

  SetAlertVisualState(true)

  if not alertState.active then
    alertState.active = true
    alertState.soundPlayed = false
    alertState.repeatTimer = 0
  end

  if not alerts.sound then
    return
  end

  if alerts.oncePerCast then
    if not alertState.soundPlayed then
      PlayAlertSound()
      alertState.soundPlayed = true
    end
  else
    alertState.repeatTimer = (alertState.repeatTimer or 0) + (elapsed or 0)
    if not alertState.soundPlayed or alertState.repeatTimer >= (alerts.repeatSeconds or 1) then
      PlayAlertSound()
      alertState.soundPlayed = true
      alertState.repeatTimer = 0
    end
  end
end

local function UpdatePanelPosition()
  if not panel then
    return
  end

  panel:ClearAllPoints()
  panel:SetPoint(
    SeaCatEchoTrackerDB.panelPoint,
    UIParent,
    SeaCatEchoTrackerDB.panelRelativePoint,
    SeaCatEchoTrackerDB.panelX,
    SeaCatEchoTrackerDB.panelY
  )
end

local function UpdateMinimapButtonPosition()
  if not minimapButton then
    return
  end

  SeaCatEchoTrackerDB.minimap = CopyDefaults(defaults.minimap, SeaCatEchoTrackerDB.minimap)

  local angle = math.rad(SeaCatEchoTrackerDB.minimap.angle or 220)
  local radius = SeaCatEchoTrackerDB.minimap.radius or 106
  local x = math.cos(angle) * radius
  local y = math.sin(angle) * radius

  minimapButton:ClearAllPoints()
  minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function UpdateStylePreview()
  if styleWidgets.countSwatch then
    styleWidgets.countSwatch:SetColorTexture(
      SeaCatEchoTrackerDB.countColor[1],
      SeaCatEchoTrackerDB.countColor[2],
      SeaCatEchoTrackerDB.countColor[3],
      1
    )
  end

  if styleWidgets.timerSwatch then
    styleWidgets.timerSwatch:SetColorTexture(
      SeaCatEchoTrackerDB.timerColor[1],
      SeaCatEchoTrackerDB.timerColor[2],
      SeaCatEchoTrackerDB.timerColor[3],
      1
    )
  end
end

local function SetRadialCooldown(cooldownFrame, startTime, duration, remaining)
  if not cooldownFrame then
    return
  end

  cooldownFrame:SetDrawEdge(false)
  if cooldownFrame.SetDrawSwipe then
    cooldownFrame:SetDrawSwipe(SeaCatEchoTrackerDB.showRadial ~= false)
  end
  if cooldownFrame.SetDrawBling then
    cooldownFrame:SetDrawBling(false)
  end
  if cooldownFrame.SetUseCircularEdge then
    cooldownFrame:SetUseCircularEdge(false)
  end
  if cooldownFrame.SetHideCountdownNumbers then
    cooldownFrame:SetHideCountdownNumbers(true)
  end

  local baseAlpha = math.max(0, math.min(1, (SeaCatEchoTrackerDB.radialOpacity or defaults.radialOpacity) / 100))
  local swipeAlpha = baseAlpha

  if SeaCatEchoTrackerDB.radialFade ~= false and duration and duration > 0 and remaining ~= nil then
    swipeAlpha = baseAlpha * math.max(0, math.min(1, remaining / duration))
  end

  if cooldownFrame.SetSwipeColor then
    cooldownFrame:SetSwipeColor(0, 0, 0, swipeAlpha)
  end

  if SeaCatEchoTrackerDB.showRadial == false then
    if cooldownFrame.Clear then
      cooldownFrame:Clear()
    elseif CooldownFrame_Clear then
      CooldownFrame_Clear(cooldownFrame)
    else
      cooldownFrame:SetCooldown(0, 0)
    end
    cooldownFrame:Hide()
    return
  end

  if startTime and duration and duration > 0 then
    cooldownFrame:Show()
    cooldownFrame:SetCooldown(startTime, duration)
  else
    if cooldownFrame.Clear then
      cooldownFrame:Clear()
    elseif CooldownFrame_Clear then
      CooldownFrame_Clear(cooldownFrame)
    else
      cooldownFrame:SetCooldown(0, 0)
    end
    cooldownFrame:Hide()
  end
end

local function UpdatePanelPreview()
  if not panelPreview.frame then
    return
  end

  SeaCatEchoTrackerDB.showPreview = true
  EnsureAlertSettings()

  panelPreview.frame:Show()
  if panel.previewDivider then
    panel.previewDivider:Show()
  end

  local previewSize = math.max(40, math.min(SeaCatEchoTrackerDB.frameSize, 84))
  local previewCountSize, previewTimerSize = GetAutoTextSizes(previewSize)
  panelPreview.icon:SetSize(previewSize, previewSize)

  panelPreview.countText:ClearAllPoints()
  panelPreview.countText:SetPoint("CENTER", panelPreview.icon, "CENTER", SeaCatEchoTrackerDB.countOffsetX, SeaCatEchoTrackerDB.countOffsetY)

  panelPreview.timeText:ClearAllPoints()
  panelPreview.timeText:SetPoint("BOTTOMRIGHT", panelPreview.icon, "BOTTOMRIGHT", SeaCatEchoTrackerDB.timerOffsetX, SeaCatEchoTrackerDB.timerOffsetY)

  SafeSetFont(panelPreview.countText, SeaCatEchoTrackerDB.fontPath, previewCountSize, "OUTLINE")
  SafeSetFont(panelPreview.timeText, SeaCatEchoTrackerDB.fontPath, previewTimerSize, "OUTLINE")

  panelPreview.countText:SetTextColor(unpackFunc(SeaCatEchoTrackerDB.countColor))

  local previewThreshold = SeaCatEchoTrackerDB.alerts and SeaCatEchoTrackerDB.alerts.threshold or defaults.alerts.threshold
  if AlertIsEnabled() and previewThreshold >= 4 then
    panelPreview.timeText:SetTextColor(GetAlertTextColor())
  else
    panelPreview.timeText:SetTextColor(unpackFunc(SeaCatEchoTrackerDB.timerColor))
  end

  panelPreview.countText:SetText("7")
  panelPreview.timeText:SetText("3.5")

  local previewDuration = 8
  local previewRemaining = 3.5
  SetRadialCooldown(panelPreview.radialCooldown, GetTime() - (previewDuration - previewRemaining), previewDuration, previewRemaining)

  UpdateAlertVisualColor()

  if panelPreview.alertGlow then
    if AlertIsEnabled() and SeaCatEchoTrackerDB.alerts.glow then
      panelPreview.alertGlow:Show()
    else
      panelPreview.alertGlow:Hide()
    end
  end

  if panelPreview.frame and panelPreview.frame.echoTrackerPulse then
    if AlertIsEnabled() and SeaCatEchoTrackerDB.alerts.pulse then
      if not panelPreview.frame.echoTrackerPulse:IsPlaying() then
        panelPreview.frame.echoTrackerPulse:Play()
      end
    else
      panelPreview.frame.echoTrackerPulse:Stop()
      panelPreview.frame:SetScale(1)
    end
  end
end

local function ApplySettings()
  EnsureAlertSettings()

  if not frame then
    return
  end

  SeaCatEchoTrackerDB.showPreview = true
  EnsureAlertSettings()

  local countSize, timerSize = GetAutoTextSizes(SeaCatEchoTrackerDB.frameSize)

  frame:ClearAllPoints()
  frame:SetPoint(
    SeaCatEchoTrackerDB.point,
    UIParent,
    SeaCatEchoTrackerDB.relativePoint,
    SeaCatEchoTrackerDB.x,
    SeaCatEchoTrackerDB.y
  )
  frame:SetSize(SeaCatEchoTrackerDB.frameSize, SeaCatEchoTrackerDB.frameSize)

  if frame.radialCooldown then
    frame.radialCooldown:SetAllPoints(frame.icon)
    if SeaCatEchoTrackerDB.showRadial == false then
      SetRadialCooldown(frame.radialCooldown)
    end
  end

  frame.countText:ClearAllPoints()
  frame.countText:SetPoint("CENTER", frame, "CENTER", SeaCatEchoTrackerDB.countOffsetX, SeaCatEchoTrackerDB.countOffsetY)

  frame.timeText:ClearAllPoints()
  frame.timeText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", SeaCatEchoTrackerDB.timerOffsetX, SeaCatEchoTrackerDB.timerOffsetY)

  SafeSetFont(frame.countText, SeaCatEchoTrackerDB.fontPath, countSize, "OUTLINE")
  SafeSetFont(frame.timeText, SeaCatEchoTrackerDB.fontPath, timerSize, "OUTLINE")

  frame.countText:SetTextColor(unpackFunc(SeaCatEchoTrackerDB.countColor))
  frame.timeText:SetTextColor(unpackFunc(SeaCatEchoTrackerDB.timerColor))
  UpdateAlertVisualColor()

  -- Only claim mouse input while unlocked, otherwise the invisible frame keeps
  -- swallowing clicks on whatever sits underneath it.
  frame:EnableMouse(SeaCatEchoTrackerDB.unlocked and true or false)

  if SeaCatEchoTrackerDB.unlocked then
    frame.bg:SetColorTexture(0.20, 0.55, 0.85, 0.18)
  else
    frame.bg:SetColorTexture(0, 0, 0, 0)
  end

  UpdatePanelPosition()
  UpdateStylePreview()
  UpdatePanelPreview()
end

local function CreateCenteredSectionTitle(parent, text, y)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOP", 0, y)
  label:SetText(text)
  return label
end

local function MakeSlider(name, parent, minVal, maxVal, step, width)
  local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  slider:SetMinMaxValues(minVal, maxVal)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)
  slider:SetWidth(width or 220)
  return slider
end

local function CreateCenteredNumberSlider(name, parent, text, y, minVal, maxVal, getValue, setValue)
  local slider = MakeSlider(name, parent, minVal, maxVal, 1, 220)
  slider:SetPoint("TOP", 0, y)

  _G[name .. "Low"]:SetText(tostring(minVal))
  _G[name .. "High"]:SetText(tostring(maxVal))
  _G[name .. "Text"]:SetText(text .. ": " .. tostring(getValue()))
  slider:SetValue(getValue())

  slider.refresh = function()
    local value = getValue()
    slider:SetValue(value)
    _G[name .. "Text"]:SetText(text .. ": " .. tostring(value))
  end

  slider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value + 0.5)
    setValue(value)
    _G[name .. "Text"]:SetText(text .. ": " .. tostring(value))
    ApplySettings()
  end)

  return slider
end

local function CreateMenuButton(parent, name, width, height, labelText)
  local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
  button:SetSize(width, height)
  button:SetText(labelText)
  return button
end

local function CreateCheckbox(parent, name, labelText, anchorPoint, relativeTo, relativePoint, x, y, getValue, setValue)
  local check = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
  check:SetPoint(anchorPoint, relativeTo, relativePoint, x, y)
  _G[name .. "Text"]:SetText(labelText)
  check:SetChecked(getValue())
  check:SetScript("OnClick", function(self)
    setValue(self:GetChecked() and true or false)
    ApplySettings()
  end)
  return check
end

local function GetMinimapAngle()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()

  px = px / scale
  py = py / scale

  local atan2 = math.atan2 or math.atan
  local angle = math.deg(atan2(py - my, px - mx))
  if angle < 0 then
    angle = angle + 360
  end

  return angle
end

local function SelectTab(name)
  SeaCatEchoTrackerDB.lastTab = name

  for tabName, button in pairs(tabButtons) do
    local selected = (tabName == name)

    if selected then
      button:SetBackdropColor(0.34, 0.28, 0.10, 0.95)
      button:SetBackdropBorderColor(0.90, 0.76, 0.24, 1)
      button.text:SetTextColor(1, 0.84, 0.25)
      if pages[tabName] then
        pages[tabName]:Show()
      end
    else
      button:SetBackdropColor(0.16, 0.16, 0.16, 0.95)
      button:SetBackdropBorderColor(0.30, 0.30, 0.30, 0.90)
      button.text:SetTextColor(0.88, 0.88, 0.88)
      if pages[tabName] then
        pages[tabName]:Hide()
      end
    end
  end
end

local function CreatePage(name)
  local page = CreateFrame("Frame", nil, panel)
  page:SetPoint("TOPLEFT", CONTENT_LEFT, CONTENT_TOP)
  page:SetPoint("BOTTOMRIGHT", CONTENT_RIGHT, CONTENT_BOTTOM)
  page:Hide()
  pages[name] = page
  return page
end

local function CreateSideTab(name, text, index)
  local button = CreateFrame("Button", nil, panel, "BackdropTemplate")
  button:SetSize(NAV_WIDTH, NAV_BUTTON_HEIGHT)
  button:SetPoint("TOPLEFT", NAV_LEFT, NAV_TOP - ((index - 1) * (NAV_BUTTON_HEIGHT + NAV_BUTTON_GAP)))

  button:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 10,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })

  button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  button.text:SetPoint("CENTER", 0, 0)
  button.text:SetJustifyH("CENTER")
  button.text:SetText(text)

  button:SetScript("OnClick", function()
    SelectTab(name)
  end)

  tabButtons[name] = button
  return button
end

local function CreateColorRow(parent, labelText, y, dbColorKey)
  local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
  row:SetSize(270, 34)
  row:SetPoint("TOP", 0, y)

  row:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 10,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  row:SetBackdropColor(0.11, 0.11, 0.11, 0.95)
  row:SetBackdropBorderColor(0.28, 0.28, 0.28, 0.9)

  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.label:SetPoint("LEFT", 12, 0)
  row.label:SetText(labelText)

  row.swatchBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
  row.swatchBorder:SetSize(28, 28)
  row.swatchBorder:SetPoint("RIGHT", -8, 0)
  row.swatchBorder:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
  })
  row.swatchBorder:SetBackdropColor(0, 0, 0, 1)
  row.swatchBorder:SetBackdropBorderColor(0.40, 0.40, 0.40, 1)

  row.swatch = row:CreateTexture(nil, "ARTWORK")
  row.swatch:SetPoint("TOPLEFT", row.swatchBorder, "TOPLEFT", 4, -4)
  row.swatch:SetPoint("BOTTOMRIGHT", row.swatchBorder, "BOTTOMRIGHT", -4, 4)

  local function GetColor()
    return SeaCatEchoTrackerDB[dbColorKey][1], SeaCatEchoTrackerDB[dbColorKey][2], SeaCatEchoTrackerDB[dbColorKey][3]
  end

  local function SetColor(r, g, b)
    SeaCatEchoTrackerDB[dbColorKey][1] = r
    SeaCatEchoTrackerDB[dbColorKey][2] = g
    SeaCatEchoTrackerDB[dbColorKey][3] = b
    ApplySettings()
  end

  row:SetScript("OnClick", function()
    local r, g, b = GetColor()

    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
      local info = {}
      info.r = r
      info.g = g
      info.b = b
      info.opacity = 1
      info.hasOpacity = false
      info.previousValues = { r = r, g = g, b = b }

      info.swatchFunc = function()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        SetColor(nr, ng, nb)
      end

      info.cancelFunc = function(previousValues)
        if previousValues then
          SetColor(previousValues.r, previousValues.g, previousValues.b)
        else
          SetColor(r, g, b)
        end
      end

      ColorPickerFrame:SetupColorPickerAndShow(info)
    else
      ColorPickerFrame.hasOpacity = false
      ColorPickerFrame.previousValues = { r = r, g = g, b = b }
      ColorPickerFrame.func = function()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        SetColor(nr, ng, nb)
      end
      ColorPickerFrame.cancelFunc = function(previousValues)
        if previousValues then
          SetColor(previousValues.r, previousValues.g, previousValues.b)
        else
          SetColor(r, g, b)
        end
      end
      ColorPickerFrame:SetColorRGB(r, g, b)
      ColorPickerFrame:Hide()
      ColorPickerFrame:Show()
    end
  end)

  return row
end

local function CreateNestedColorRow(parent, labelText, y, getter, setter)
  local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
  row:SetSize(270, 34)
  row:SetPoint("TOP", 0, y)

  row:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 10,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  row:SetBackdropColor(0.11, 0.11, 0.11, 0.95)
  row:SetBackdropBorderColor(0.28, 0.28, 0.28, 0.9)

  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.label:SetPoint("LEFT", 12, 0)
  row.label:SetText(labelText)

  row.swatchBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
  row.swatchBorder:SetSize(28, 28)
  row.swatchBorder:SetPoint("RIGHT", -8, 0)
  row.swatchBorder:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
  })
  row.swatchBorder:SetBackdropColor(0, 0, 0, 1)
  row.swatchBorder:SetBackdropBorderColor(0.40, 0.40, 0.40, 1)

  row.swatch = row:CreateTexture(nil, "ARTWORK")
  row.swatch:SetPoint("TOPLEFT", row.swatchBorder, "TOPLEFT", 4, -4)
  row.swatch:SetPoint("BOTTOMRIGHT", row.swatchBorder, "BOTTOMRIGHT", -4, 4)

  row:SetScript("OnClick", function()
    local r, g, b = getter()

    local function SetColor(nr, ng, nb)
      setter(nr, ng, nb)
      ApplySettings()
    end

    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
      local info = {}
      info.r = r
      info.g = g
      info.b = b
      info.opacity = 1
      info.hasOpacity = false
      info.previousValues = { r = r, g = g, b = b }

      info.swatchFunc = function()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        SetColor(nr, ng, nb)
      end

      info.cancelFunc = function(previousValues)
        if previousValues then
          SetColor(previousValues.r, previousValues.g, previousValues.b)
        else
          SetColor(r, g, b)
        end
      end

      ColorPickerFrame:SetupColorPickerAndShow(info)
    else
      ColorPickerFrame.hasOpacity = false
      ColorPickerFrame.previousValues = { r = r, g = g, b = b }
      ColorPickerFrame.func = function()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        SetColor(nr, ng, nb)
      end
      ColorPickerFrame.cancelFunc = function(previousValues)
        if previousValues then
          SetColor(previousValues.r, previousValues.g, previousValues.b)
        else
          SetColor(r, g, b)
        end
      end
      ColorPickerFrame:SetColorRGB(r, g, b)
      ColorPickerFrame:Hide()
      ColorPickerFrame:Show()
    end
  end)

  return row
end

local function RefreshFontDropdown()
  if not controls.fontDropdown then
    return
  end

  for _, info in ipairs(FONT_OPTIONS) do
    if info.value == SeaCatEchoTrackerDB.fontPath then
      UIDropDownMenu_SetText(controls.fontDropdown, info.text)
      return
    end
  end

  UIDropDownMenu_SetText(controls.fontDropdown, L["Default"])
end


local function RefreshControls()
  if controls.frameSizeSlider and controls.frameSizeSlider.refresh then
    controls.frameSizeSlider.refresh()
  end
  if controls.countSizeSlider and controls.countSizeSlider.refresh then
    controls.countSizeSlider.refresh()
  end
  if controls.countOffsetXSlider and controls.countOffsetXSlider.refresh then
    controls.countOffsetXSlider.refresh()
  end
  if controls.countOffsetYSlider and controls.countOffsetYSlider.refresh then
    controls.countOffsetYSlider.refresh()
  end
  if controls.timerSizeSlider and controls.timerSizeSlider.refresh then
    controls.timerSizeSlider.refresh()
  end
  if controls.timerOffsetXSlider and controls.timerOffsetXSlider.refresh then
    controls.timerOffsetXSlider.refresh()
  end
  if controls.timerOffsetYSlider and controls.timerOffsetYSlider.refresh then
    controls.timerOffsetYSlider.refresh()
  end
  if controls.radialOpacitySlider and controls.radialOpacitySlider.refresh then
    controls.radialOpacitySlider.refresh()
  end

  if controls.alwaysShowCheck then
    controls.alwaysShowCheck:SetChecked(SeaCatEchoTrackerDB.alwaysShow)
  end
  if controls.showRadialCheck then
    controls.showRadialCheck:SetChecked(SeaCatEchoTrackerDB.showRadial ~= false)
  end
  if controls.radialFadeCheck then
    controls.radialFadeCheck:SetChecked(SeaCatEchoTrackerDB.radialFade ~= false)
  end

  if controls.hideMinimapCheck then
    controls.hideMinimapCheck:SetChecked(SeaCatEchoTrackerDB.minimap.hide)
  end

  if controls.countOutsideRaidCheck then
    controls.countOutsideRaidCheck:SetChecked(SeaCatEchoTrackerDB.countOutsideRaid and true or false)
  end

  if controls.alertEnabledCheck then
    controls.alertEnabledCheck:SetChecked(AlertIsEnabled())
  end
  if controls.alertGlowCheck then
    controls.alertGlowCheck:SetChecked(SeaCatEchoTrackerDB.alerts.glow)
  end
  if controls.alertPulseCheck then
    controls.alertPulseCheck:SetChecked(SeaCatEchoTrackerDB.alerts.pulse)
  end
  if controls.alertSoundCheck then
    controls.alertSoundCheck:SetChecked(SeaCatEchoTrackerDB.alerts.sound)
  end
  if controls.alertOncePerCastCheck then
    controls.alertOncePerCastCheck:SetChecked(EnsureAlertSettings().oncePerCast)
  end
  if controls.alertThresholdSlider and controls.alertThresholdSlider.refresh then
    controls.alertThresholdSlider.refresh()
  end
  if styleWidgets.alertTextSwatch then
    styleWidgets.alertTextSwatch:SetColorTexture(
      SeaCatEchoTrackerDB.alerts.textColor[1],
      SeaCatEchoTrackerDB.alerts.textColor[2],
      SeaCatEchoTrackerDB.alerts.textColor[3],
      1
    )
  end
  if styleWidgets.alertGlowSwatch then
    styleWidgets.alertGlowSwatch:SetColorTexture(
      SeaCatEchoTrackerDB.alerts.glowColor[1],
      SeaCatEchoTrackerDB.alerts.glowColor[2],
      SeaCatEchoTrackerDB.alerts.glowColor[3],
      1
    )
  end

  if unlockButton then
    unlockButton:SetText(SeaCatEchoTrackerDB.unlocked and L["Lock Frame"] or L["Unlock Frame"])
  end

  RefreshFontDropdown()
  if controls.alertRepeatSlider and controls.alertRepeatSlider.refresh then
    controls.alertRepeatSlider.refresh()
  end
  if controls.alertSoundChannelDropdown then
    UIDropDownMenu_SetText(controls.alertSoundChannelDropdown, GetSoundChannelLabel(EnsureAlertSettings().soundChannel))
  end
  UpdateStylePreview()
  UpdatePanelPreview()
end

local function ResetToDefaults()
  local currentPanelPoint = SeaCatEchoTrackerDB.panelPoint
  local currentPanelRelativePoint = SeaCatEchoTrackerDB.panelRelativePoint
  local currentPanelX = SeaCatEchoTrackerDB.panelX
  local currentPanelY = SeaCatEchoTrackerDB.panelY
  local currentLastTab = SeaCatEchoTrackerDB.lastTab or "general"
  -- The calibrated duration is a measured fact, not a preference; wiping it
  -- would just force another out-of-combat relearn.
  local currentEchoDuration = SeaCatEchoTrackerDB.echoDuration

  SeaCatEchoTrackerDB = CopyDefaults(defaults, {})
  SeaCatEchoTrackerDB.minimap = CopyDefaults(defaults.minimap, {})
  SeaCatEchoTrackerDB.echoDuration = currentEchoDuration

  SeaCatEchoTrackerDB.panelPoint = currentPanelPoint
  SeaCatEchoTrackerDB.panelRelativePoint = currentPanelRelativePoint
  SeaCatEchoTrackerDB.panelX = currentPanelX
  SeaCatEchoTrackerDB.panelY = currentPanelY
  SeaCatEchoTrackerDB.lastTab = currentLastTab
  SeaCatEchoTrackerDB.showPreview = true
  EnsureAlertSettings()

  if minimapButton then
    if SeaCatEchoTrackerDB.minimap.hide then
      minimapButton:Hide()
    else
      minimapButton:Show()
    end
  end

  alertState.active = false
  alertState.soundPlayed = false

  UpdateMinimapButtonPosition()
  RefreshControls()
  ApplySettings()
  SelectTab(SeaCatEchoTrackerDB.lastTab or "general")
end

frame = CreateFrame("Frame", "SeaCatEchoTrackerFrame", UIParent)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(false)
frame:RegisterForDrag("LeftButton")

frame:SetScript("OnDragStart", function(self)
  if SeaCatEchoTrackerDB.unlocked then
    self:StartMoving()
  end
end)

-- StartMoving re-anchors the frame to whichever corner it likes (TOPLEFT in
-- practice), so storing GetPoint() verbatim saves a TOPLEFT offset under keys
-- that everything else reads as CENTER-relative. Converting back to a CENTER
-- offset keeps every stored position in one coordinate space.
local function SaveFramePosition()
  if not frame then
    return
  end

  local fx, fy = frame:GetCenter()
  local ux, uy = UIParent:GetCenter()
  if not fx or not ux then
    return
  end

  local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()

  SeaCatEchoTrackerDB.point = "CENTER"
  SeaCatEchoTrackerDB.relativePoint = "CENTER"
  SeaCatEchoTrackerDB.x = fx * scale - ux
  SeaCatEchoTrackerDB.y = fy * scale - uy
end

frame:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  SaveFramePosition()
end)

frame.icon = frame:CreateTexture(nil, "BACKGROUND")
frame.icon:SetAllPoints()
frame.icon:SetTexture(ECHO_ICON)

frame.radialCooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
frame.radialCooldown:SetAllPoints(frame.icon)
frame.radialCooldown:SetReverse(true)
frame.radialCooldown:SetFrameStrata(frame:GetFrameStrata())
frame.radialCooldown:SetFrameLevel(frame:GetFrameLevel() + 2)
frame.radialCooldown:Hide()

frame.bg = frame:CreateTexture(nil, "BORDER")
frame.bg:SetAllPoints()
frame.bg:SetColorTexture(0, 0, 0, 0)

frame.alertGlow = CreateSoftGlowContainer(frame, frame.icon)

frame.textOverlay = CreateFrame("Frame", nil, frame)
frame.textOverlay:SetAllPoints(frame)
frame.textOverlay:SetFrameStrata(frame:GetFrameStrata())
frame.textOverlay:SetFrameLevel(frame.radialCooldown:GetFrameLevel() + 10)

frame.countText = frame.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.countText:SetText("")

frame.timeText = frame.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
frame.timeText:SetText("")

ApplySettings()
frame:Show()
EnsurePulseAnimation(frame)

-- Echo state is inferred from the player's own cast sequence instead of read
-- from auras. Aura data is fully secret in combat/encounters/M+/PvP as of 12.1,
-- but a unit's cast info is only secret when that unit is not the player or
-- their pet, so everything below stays plain-valued.
do
  local RENDER_INTERVAL = 0.1
  local MAX_PENDING = 64

  local renderThrottle = 0

  -- castGUID -> target name. UNIT_SPELLCAST_SUCCEEDED carries no target, so the
  -- name has to be captured from UNIT_SPELLCAST_SENT and looked up on success.
  local pendingTargets = {}
  local pendingCount = 0

  -- target name -> expiry. Re-casting on the same target refreshes rather than
  -- stacks, which is exactly this table's overwrite behaviour.
  local targeted = {}

  -- Echoes whose recipients are unknown: Temporal Anomaly's orb (5 allies), the
  -- extra ally from an Emerald Blossom stack, and any cast whose target could
  -- not be resolved. Each entry is { expiry, count } since expiry is known but
  -- the identities are not, which also means these cannot be deduped.
  local batches = {}

  -- Buff 1242759. All stacks share a single timer that every Emerald Blossom
  -- cast refreshes, so this is a count plus one expiry rather than a list.
  local extraTargetStacks = 0
  local extraTargetExpiry = 0

  local function GetEchoDuration()
    local calibrated = SeaCatEchoTrackerDB.echoDuration
    if type(calibrated) == "number" and calibrated > 0 then
      return calibrated
    end
    return ECHO_DURATION_FALLBACK
  end

  ns.GetEchoDuration = GetEchoDuration

  -- Only Echo itself is cleared here. The Emerald Blossom stacks are a separate
  -- resource that only an Echo cast consumes, so they survive this.
  local function ClearAll()
    wipe(targeted)
    wipe(batches)
  end

  -- Shared timer means the whole buff falls off at once, not stack by stack.
  local function PruneExtraTargetStacks(now)
    if extraTargetStacks > 0 and extraTargetExpiry <= now then
      extraTargetStacks = 0
      extraTargetExpiry = 0
    end
  end

  local function Prune(now)
    for target, expiry in pairs(targeted) do
      if expiry <= now then
        targeted[target] = nil
      end
    end

    for i = #batches, 1, -1 do
      if batches[i].expiry <= now then
        table.remove(batches, i)
      end
    end

    PruneExtraTargetStacks(now)
  end

  local function AddBatch(expiry, count)
    batches[#batches + 1] = { expiry = expiry, count = count }
  end

  local function GetEarliestExpiry()
    local earliest = nil

    for _, expiry in pairs(targeted) do
      if not earliest or expiry < earliest then
        earliest = expiry
      end
    end

    for _, batch in ipairs(batches) do
      if not earliest or batch.expiry < earliest then
        earliest = batch.expiry
      end
    end

    return earliest
  end

  -- Deliberately an estimate. Temporal Anomaly contributes a flat 5 without
  -- telling us who got hit, so a later Echo on one of those same allies is a
  -- refresh that gets counted as a new application. The bias is upward, which
  -- is the opposite direction from the timer's bias.
  local function CountEchoes()
    local n = 0

    for _ in pairs(targeted) do
      n = n + 1
    end

    for _, batch in ipairs(batches) do
      n = n + batch.count
    end

    return n
  end

  -- Outside a raid the orb often clips fewer than 5, which inflates the count,
  -- so it stays hidden there unless the player opts in.
  local function ShouldShowCount()
    if SeaCatEchoTrackerDB.countOutsideRaid then
      return true
    end

    local _, instanceType = IsInInstance()
    return instanceType == "raid"
  end

  -- SENT hands us a name string rather than a unit token, so friendliness is
  -- resolved by matching against the group. Party/raid members are exempt from
  -- unit identity secrecy outside PvP, making these reads safe.
  local function IsGroupMemberName(name)
    if type(name) ~= "string" or IsSecret(name) then
      return false
    end

    local playerName = UnitName("player")
    if not IsSecret(playerName) and playerName == name then
      return true
    end

    local prefix, size = "party", 4
    if IsInRaid() then
      prefix, size = "raid", 40
    end

    for i = 1, size do
      local unit = prefix .. i
      if UnitExists(unit) then
        local unitName = UnitName(unit)
        if not IsSecret(unitName) and unitName == name then
          return true
        end
      end
    end

    return false
  end

  -- Out of combat the aura fields are plain values, so Echo's real duration can
  -- be read once and reused through the next restricted period. This is what
  -- keeps talent 376240's +15%/point out of the code as a hardcoded number.
  local function CalibrateDuration()
    if InCombatLockdown() then
      return
    end

    if not (C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID) then
      return
    end

    local function readFrom(unit)
      if not UnitExists(unit) then
        return nil
      end

      local aura = C_UnitAuras.GetUnitAuraBySpellID(unit, ECHO_SPELL_ID)
      if not aura then
        return nil
      end

      local duration = aura.duration
      if IsSecret(duration) or type(duration) ~= "number" or duration <= 0 then
        return nil
      end

      return duration
    end

    local found = readFrom("player")

    if not found then
      local prefix, size = "party", 4
      if IsInRaid() then
        prefix, size = "raid", 40
      end

      for i = 1, size do
        found = readFrom(prefix .. i)
        if found then
          break
        end
      end
    end

    if found then
      SeaCatEchoTrackerDB.echoDuration = found
    end
  end

  local function RememberTarget(castGUID, target)
    -- A cast that never completes leaves its entry behind, so cap the table
    -- instead of letting a long fight grow it without bound.
    if pendingCount >= MAX_PENDING then
      wipe(pendingTargets)
      pendingCount = 0
    end

    pendingTargets[castGUID] = target or true
    pendingCount = pendingCount + 1
  end

  local function TakeTarget(castGUID)
    if not castGUID then
      return nil
    end

    local target = pendingTargets[castGUID]
    pendingTargets[castGUID] = nil
    return target
  end

  local function ResolveCast(spellID, target)
    local now = GetTime()

    if spellID == EMERALD_BLOSSOM_SPELL_ID then
      PruneExtraTargetStacks(now)

      if extraTargetStacks < EXTRA_TARGET_MAX_STACKS then
        extraTargetStacks = extraTargetStacks + 1
      end

      -- Refreshed even at max stacks: re-casting extends the existing buff.
      extraTargetExpiry = now + EXTRA_TARGET_DURATION
      return
    end

    local applyKind = APPLY_SPELLS[spellID]
    if applyKind then
      local expiry = now + GetEchoDuration()

      if applyKind == "batch" then
        AddBatch(expiry, TEMPORAL_ANOMALY_TARGETS)
      else
        if type(target) == "string" then
          targeted[target] = expiry
        else
          AddBatch(expiry, 1)
        end

        -- Spend one Emerald Blossom stack: the extra ally is picked by the game,
        -- so it can only be tracked as an anonymous entry. Spending a stack does
        -- not shorten the shared timer on whatever is left.
        PruneExtraTargetStacks(now)
        if extraTargetStacks > 0 then
          extraTargetStacks = extraTargetStacks - 1
          if extraTargetStacks == 0 then
            extraTargetExpiry = 0
          end
          AddBatch(expiry, 1)
        end
      end

      -- Learn the real duration from the aura we just applied, once the server
      -- has had a moment to actually put it there.
      if not InCombatLockdown() and C_Timer and C_Timer.After then
        C_Timer.After(0.3, CalibrateDuration)
      end

      return
    end

    local consumeKind = CONSUME_SPELLS[spellID]
    if not consumeKind then
      return
    end

    if consumeKind == "always" then
      ClearAll()
      return
    end

    -- Living Flame only consumes Echo on a friendly target. When the target
    -- cannot be resolved, do nothing: keeping a stale timer is the conservative
    -- error, dropping a live one is not.
    if consumeKind == "friendly" and IsGroupMemberName(target) then
      ClearAll()
    end
  end

  local function OnCastSucceeded(castGUID, spellID)
    -- An empowered spell has only started charging at this point; acting now
    -- would consume Echo even if the channel is later cancelled. Its target
    -- mapping is deliberately left in place for EMPOWER_STOP to pick up.
    if EMPOWERED_SPELLS[spellID] then
      return
    end

    ResolveCast(spellID, TakeTarget(castGUID))
  end

  local function OnEmpowerStop(castGUID, spellID, complete)
    local target = TakeTarget(castGUID)

    -- complete is plain for the player's own casts, but this addon has been
    -- bitten by secrets twice already; a boolean test on one would throw.
    if IsSecret(complete) then
      return
    end

    -- Cancelled or interrupted mid-charge: the spell never went off.
    if complete then
      ResolveCast(spellID, target)
    end
  end

  local watcher = CreateFrame("Frame")
  watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  watcher:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
  watcher:RegisterEvent("UNIT_SPELLCAST_SENT")
  watcher:RegisterEvent("PLAYER_REGEN_ENABLED")

  watcher:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
      -- Payload order differs from SUCCEEDED: unit, target, castGUID, spellID.
      -- SENT also cannot be unit-filtered, so the check happens here.
      local unit, target, castGUID = ...
      if unit == "player" and castGUID then
        RememberTarget(castGUID, target)
      end
      return
    end

    if event == "PLAYER_REGEN_ENABLED" then
      CalibrateDuration()
      return
    end

    if event == "UNIT_SPELLCAST_EMPOWER_STOP" then
      local _, castGUID, spellID, complete = ...
      if spellID then
        OnEmpowerStop(castGUID, spellID, complete)
      end
      return
    end

    local _, castGUID, spellID = ...
    if spellID then
      OnCastSucceeded(castGUID, spellID)
    end
  end)

  frame:SetScript("OnUpdate", function(self, elapsed)
    renderThrottle = renderThrottle + elapsed
    if renderThrottle < RENDER_INTERVAL then
      return
    end

    local step = renderThrottle
    renderThrottle = 0

    if SeaCatEchoTrackerDB.unlocked then
      self.countText:SetText("12")
      self.timeText:SetText("5.8")
      self.timeText:SetTextColor(unpackFunc(SeaCatEchoTrackerDB.timerColor))
      SetRadialCooldown(self.radialCooldown, GetTime() - 2.2, 8, 5.8)
      UpdateAlertState(false)
      self:SetAlpha(1)
      return
    end

    local now = GetTime()
    Prune(now)

    local earliest = GetEarliestExpiry()
    local remaining = earliest and (earliest - now) or nil

    local count = CountEchoes()
    if count > 0 and ShouldShowCount() then
      self.countText:SetText(tostring(count))
    else
      self.countText:SetText("")
    end

    local alertActive = false
    local alertThreshold = SeaCatEchoTrackerDB.alerts and SeaCatEchoTrackerDB.alerts.threshold or defaults.alerts.threshold

    if remaining and remaining > 0 then
      self.timeText:SetText(string.format("%.1f", remaining))

      local duration = GetEchoDuration()
      SetRadialCooldown(self.radialCooldown, earliest - duration, duration, remaining)

      if AlertIsEnabled() and remaining <= alertThreshold then
        self.timeText:SetTextColor(GetAlertTextColor())
        alertActive = true
      else
        self.timeText:SetTextColor(unpackFunc(SeaCatEchoTrackerDB.timerColor))
      end
    else
      self.timeText:SetText("")
      self.timeText:SetTextColor(unpackFunc(SeaCatEchoTrackerDB.timerColor))
      SetRadialCooldown(self.radialCooldown)
    end

    UpdateAlertState(alertActive, step)

    if SeaCatEchoTrackerDB.alwaysShow or earliest then
      self:SetAlpha(1)
    else
      self:SetAlpha(0)
    end
  end)
end

panel = CreateFrame("Frame", "SeaCatEchoTrackerOptionsPanel", UIParent, "BackdropTemplate")
panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
panel:SetFrameStrata("DIALOG")
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetPropagateKeyboardInput(true)
panel:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true,
  tileSize = 16,
  edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
panel:SetBackdropColor(0.16, 0.16, 0.17, 0.96)
panel:Hide()

panel:SetScript("OnDragStart", function(self)
  self:StartMoving()
end)

panel:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, relativePoint, x, y = self:GetPoint()
  SeaCatEchoTrackerDB.panelPoint = point
  SeaCatEchoTrackerDB.panelRelativePoint = relativePoint
  SeaCatEchoTrackerDB.panelX = x
  SeaCatEchoTrackerDB.panelY = y
end)

-- Consume only ESCAPE; every other key has to keep reaching the game or all
-- keybinds break while the panel is open.
--
-- SetPropagateKeyboardInput is protected in combat, so calling it here while
-- locked down raises ADDON_ACTION_BLOCKED and taints whatever runs next. In
-- combat we skip the call and let every key through, which costs only the
-- ability to close the panel with ESCAPE until combat ends.
panel:SetScript("OnKeyDown", function(self, key)
  if InCombatLockdown() then
    return
  end

  if key == "ESCAPE" then
    self:SetPropagateKeyboardInput(false)
    self:Hide()
  else
    self:SetPropagateKeyboardInput(true)
  end
end)

panel.topShade = panel:CreateTexture(nil, "BORDER")
panel.topShade:SetPoint("TOPLEFT", 8, -8)
panel.topShade:SetPoint("TOPRIGHT", -8, -8)
panel.topShade:SetHeight(46)
panel.topShade:SetColorTexture(0.24, 0.24, 0.25, 0.92)

panel.leftShade = panel:CreateTexture(nil, "BORDER")
panel.leftShade:SetPoint("TOPLEFT", 12, -58)
panel.leftShade:SetPoint("BOTTOMLEFT", 12, 12)
panel.leftShade:SetWidth(118)
panel.leftShade:SetColorTexture(0.12, 0.12, 0.12, 0.80)

panel.divider = panel:CreateTexture(nil, "BORDER")
panel.divider:SetPoint("TOPLEFT", 136, -58)
panel.divider:SetPoint("BOTTOMLEFT", 136, 12)
panel.divider:SetWidth(1)
panel.divider:SetColorTexture(0.34, 0.34, 0.34, 0.75)

panel.previewDivider = panel:CreateTexture(nil, "BORDER")
panel.previewDivider:SetPoint("TOPRIGHT", -128, -58)
panel.previewDivider:SetPoint("BOTTOMRIGHT", -128, 48)
panel.previewDivider:SetWidth(1)
panel.previewDivider:SetColorTexture(0.34, 0.34, 0.34, 0.55)

panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
panel.title:SetPoint("TOP", 0, -18)
panel.title:SetText(L["Echo Tracker"])

panel.subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
panel.subtitle:SetPoint("TOP", 0, -36)
panel.subtitle:SetText(L["Drag window to move"])

local closeButton = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", -6, -6)

panelPreview.frame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
panelPreview.frame:SetSize(100, 140)
panelPreview.frame:SetPoint("TOPRIGHT", -14, -78)
panelPreview.frame:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true,
  tileSize = 16,
  edgeSize = 10,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
panelPreview.frame:SetBackdropColor(0.10, 0.10, 0.10, 0.94)
panelPreview.frame:SetBackdropBorderColor(0.28, 0.28, 0.28, 0.9)
panelPreview.frame:EnableMouse(true)

panelPreview.label = panelPreview.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
panelPreview.label:SetPoint("TOP", 0, -10)
panelPreview.label:SetText(L["Live Preview"])

panelPreview.icon = panelPreview.frame:CreateTexture(nil, "ARTWORK")
panelPreview.icon:SetPoint("TOP", 0, -34)
panelPreview.icon:SetSize(64, 64)
panelPreview.icon:SetTexture(ECHO_ICON)

panelPreview.radialCooldown = CreateFrame("Cooldown", nil, panelPreview.frame, "CooldownFrameTemplate")
panelPreview.radialCooldown:SetAllPoints(panelPreview.icon)
panelPreview.radialCooldown:SetReverse(true)
panelPreview.radialCooldown:SetFrameStrata(panelPreview.frame:GetFrameStrata())
panelPreview.radialCooldown:SetFrameLevel(panelPreview.frame:GetFrameLevel() + 2)
panelPreview.radialCooldown:Hide()

panelPreview.alertGlow = CreateSoftGlowContainer(panelPreview.frame, panelPreview.icon)

panelPreview.countText = panelPreview.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
panelPreview.countText:SetText("7")

panelPreview.timeText = panelPreview.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
panelPreview.timeText:SetText("3.5")

panelPreview.help = panelPreview.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
panelPreview.help:SetPoint("BOTTOM", 0, 10)
panelPreview.help:SetText(L["Echo Preview"])

panelPreview.frame:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(L["Live Preview"])
  GameTooltip:AddLine(L["Large number: Echo count"], 1, 1, 1)
  GameTooltip:AddLine(L["Small number: lowest Echo duration"], 1, 1, 1)
  GameTooltip:AddLine(L["Updates as you change text, size, font, and color."], 0.8, 0.8, 0.8, true)
  GameTooltip:Show()
end)

panelPreview.frame:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

EnsurePulseAnimation(panelPreview.frame)

panel:SetScript("OnShow", function(self)
  if not InCombatLockdown() then
    self:SetPropagateKeyboardInput(true)
  end
  UpdatePanelPreview()
  SelectTab(SeaCatEchoTrackerDB.lastTab or "general")
end)

panel:SetScript("OnHide", function()
  SeaCatEchoTrackerDB.unlocked = false
  if unlockButton then
    unlockButton:SetText(L["Unlock Frame"])
  end
  ApplySettings()
end)

ApplySettings()

local generalPage = CreatePage("general")
local stylePage = CreatePage("style")
local textPage = CreatePage("text")
local alertsPage = CreatePage("alerts")
local soundPage = CreatePage("sound")

CreateSideTab("general", L["General"], 1)
CreateSideTab("style", L["Style"], 2)
CreateSideTab("text", L["Text"], 3)
CreateSideTab("alerts", L["Alerts"], 4)
CreateSideTab("sound", L["Sound"], 5)

CreateCenteredSectionTitle(generalPage, L["Frame"], -8)

controls.frameSizeSlider = CreateCenteredNumberSlider(
  "SeaCatEchoTrackerFrameSizeSlider",
  generalPage,
  L["Icon Size"],
  -36,
  32,
  128,
  function()
    return SeaCatEchoTrackerDB.frameSize
  end,
  function(v)
    SeaCatEchoTrackerDB.frameSize = v
  end
)

unlockButton = CreateMenuButton(generalPage, "SeaCatEchoTrackerUnlockButton", 150, 26, L["Unlock Frame"])
unlockButton:SetPoint("TOP", -78, -112)
unlockButton:SetScript("OnClick", function(self)
  SeaCatEchoTrackerDB.unlocked = not SeaCatEchoTrackerDB.unlocked
  self:SetText(SeaCatEchoTrackerDB.unlocked and L["Lock Frame"] or L["Unlock Frame"])
  ApplySettings()
end)

controls.alwaysShowCheck = CreateFrame("CheckButton", "SeaCatEchoTrackerAlwaysShowCheck", generalPage, "UICheckButtonTemplate")
controls.alwaysShowCheck:SetPoint("LEFT", unlockButton, "RIGHT", 32, 0)
SeaCatEchoTrackerAlwaysShowCheckText:SetText(L["Always Show"])
controls.alwaysShowCheck:SetChecked(SeaCatEchoTrackerDB.alwaysShow)
controls.alwaysShowCheck:SetScript("OnClick", function(self)
  SeaCatEchoTrackerDB.alwaysShow = self:GetChecked() and true or false
  ApplySettings()
end)


CreateCenteredSectionTitle(generalPage, L["Minimap"], -220)

controls.hideMinimapCheck = CreateFrame("CheckButton", "SeaCatEchoTrackerHideMinimapCheck", generalPage, "UICheckButtonTemplate")
controls.hideMinimapCheck:SetPoint("TOP", 0, -248)
SeaCatEchoTrackerHideMinimapCheckText:SetText(L["Hide Minimap Button"])
controls.hideMinimapCheck:SetChecked(SeaCatEchoTrackerDB.minimap.hide)
controls.hideMinimapCheck:SetScript("OnClick", function(self)
  SeaCatEchoTrackerDB.minimap.hide = self:GetChecked() and true or false
  if minimapButton then
    if SeaCatEchoTrackerDB.minimap.hide then
      minimapButton:Hide()
    else
      minimapButton:Show()
    end
  end
end)

local minimapHelp = generalPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
minimapHelp:SetPoint("TOP", 0, -284)
minimapHelp:SetText(L["Tip: drag the minimap button to reposition it."])
minimapHelp:SetTextColor(0.72, 0.72, 0.72)

CreateCenteredSectionTitle(stylePage, L["Font"], -8)

controls.fontDropdown = CreateFrame("Frame", "SeaCatEchoTrackerFontDropdown", stylePage, "UIDropDownMenuTemplate")
controls.fontDropdown:SetPoint("TOP", 0, -28)
UIDropDownMenu_SetWidth(controls.fontDropdown, 180)

UIDropDownMenu_Initialize(controls.fontDropdown, function(self, level)
  for _, info in ipairs(FONT_OPTIONS) do
    local entry = UIDropDownMenu_CreateInfo()
    entry.text = info.text
    entry.checked = (SeaCatEchoTrackerDB.fontPath == info.value)
    entry.func = function()
      SeaCatEchoTrackerDB.fontPath = info.value
      RefreshFontDropdown()
      ApplySettings()
    end
    UIDropDownMenu_AddButton(entry, level)
  end
end)

RefreshFontDropdown()

CreateCenteredSectionTitle(stylePage, L["Colors"], -120)

local countColorRow = CreateColorRow(stylePage, L["Count Color"], -150, "countColor")
local timerColorRow = CreateColorRow(stylePage, L["Timer Color"], -196, "timerColor")

styleWidgets.countSwatch = countColorRow.swatch
styleWidgets.timerSwatch = timerColorRow.swatch

local colorHelp = stylePage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
colorHelp:SetPoint("TOP", 0, -250)
colorHelp:SetText(L["Click a color row to open the palette."])
colorHelp:SetTextColor(0.72, 0.72, 0.72)

CreateCenteredSectionTitle(stylePage, L["Frame"], -270)

controls.showRadialCheck = CreateFrame("CheckButton", "SeaCatEchoTrackerShowRadialCheck", stylePage, "UICheckButtonTemplate")
controls.showRadialCheck:SetPoint("TOP", 0, -300)
SeaCatEchoTrackerShowRadialCheckText:SetText(L["Enable Radial Timer"])
controls.showRadialCheck:SetChecked(SeaCatEchoTrackerDB.showRadial ~= false)
controls.showRadialCheck:SetScript("OnClick", function(self)
  SeaCatEchoTrackerDB.showRadial = self:GetChecked() and true or false
  ApplySettings()
end)

controls.radialOpacitySlider = CreateCenteredNumberSlider(
  "SeaCatEchoTrackerRadialOpacitySlider",
  stylePage,
  L["Radial Opacity"],
  -348,
  0,
  100,
  function()
    return SeaCatEchoTrackerDB.radialOpacity or defaults.radialOpacity
  end,
  function(v)
    SeaCatEchoTrackerDB.radialOpacity = v
    ApplySettings()
  end
)

controls.radialFadeCheck = CreateFrame("CheckButton", "SeaCatEchoTrackerRadialFadeCheck", stylePage, "UICheckButtonTemplate")
controls.radialFadeCheck:SetPoint("TOP", 0, -412)
SeaCatEchoTrackerRadialFadeCheckText:SetText(L["Fade Radial With Timer"])
controls.radialFadeCheck:SetChecked(SeaCatEchoTrackerDB.radialFade ~= false)
controls.radialFadeCheck:SetScript("OnClick", function(self)
  SeaCatEchoTrackerDB.radialFade = self:GetChecked() and true or false
  ApplySettings()
end)

CreateCenteredSectionTitle(textPage, L["Count Text"], -8)

controls.countSizeSlider = CreateCenteredNumberSlider(
  "SeaCatEchoTrackerCountSizeSlider",
  textPage,
  L["Count Size"],
  -36,
  -12,
  12,
  function()
    return SeaCatEchoTrackerDB.countSizeAdjust or 0
  end,
  function(v)
    SeaCatEchoTrackerDB.countSizeAdjust = v
  end
)

controls.countOffsetXSlider = CreateCenteredNumberSlider(
  "SeaCatEchoTrackerCountOffsetXSlider",
  textPage,
  L["Count X"],
  -92,
  -50,
  50,
  function()
    return SeaCatEchoTrackerDB.countOffsetX
  end,
  function(v)
    SeaCatEchoTrackerDB.countOffsetX = v
  end
)

controls.countOffsetYSlider = CreateCenteredNumberSlider(
  "SeaCatEchoTrackerCountOffsetYSlider",
  textPage,
  L["Count Y"],
  -148,
  -50,
  50,
  function()
    return SeaCatEchoTrackerDB.countOffsetY
  end,
  function(v)
    SeaCatEchoTrackerDB.countOffsetY = v
  end
)

controls.countOutsideRaidCheck = CreateCheckbox(
  textPage,
  "SeaCatEchoTrackerCountOutsideRaidCheck",
  L["Also show count outside raids"],
  "TOPLEFT",
  textPage,
  "TOPLEFT",
  54,
  -184,
  function()
    return SeaCatEchoTrackerDB.countOutsideRaid
  end,
  function(v)
    SeaCatEchoTrackerDB.countOutsideRaid = v
  end
)

local countScopeHelp = textPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
countScopeHelp:SetPoint("TOP", 0, -214)
countScopeHelp:SetWidth(300)
countScopeHelp:SetJustifyH("CENTER")
countScopeHelp:SetText(L["Outside raids Temporal Anomaly often hits fewer than 5, so the count reads high."])
countScopeHelp:SetTextColor(0.72, 0.72, 0.72)

CreateCenteredSectionTitle(textPage, L["Timer Text"], -240)

controls.timerSizeSlider = CreateCenteredNumberSlider(
  "SeaCatEchoTrackerTimerSizeSlider",
  textPage,
  L["Timer Size"],
  -268,
  -10,
  10,
  function()
    return SeaCatEchoTrackerDB.timerSizeAdjust or 0
  end,
  function(v)
    SeaCatEchoTrackerDB.timerSizeAdjust = v
  end
)

controls.timerOffsetXSlider = CreateCenteredNumberSlider(
  "SeaCatEchoTrackerTimerOffsetXSlider",
  textPage,
  L["Timer X"],
  -328,
  -50,
  50,
  function()
    return SeaCatEchoTrackerDB.timerOffsetX
  end,
  function(v)
    SeaCatEchoTrackerDB.timerOffsetX = v
  end
)

controls.timerOffsetYSlider = CreateCenteredNumberSlider(
  "SeaCatEchoTrackerTimerOffsetYSlider",
  textPage,
  L["Timer Y"],
  -388,
  -50,
  50,
  function()
    return SeaCatEchoTrackerDB.timerOffsetY
  end,
  function(v)
    SeaCatEchoTrackerDB.timerOffsetY = v
  end
)

local autoScaleHelp = textPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
autoScaleHelp:SetPoint("TOP", 0, -434)
autoScaleHelp:SetText(L["Text auto-scales with icon size. Size sliders fine-tune that scaling."])
autoScaleHelp:SetTextColor(0.72, 0.72, 0.72)

CreateCenteredSectionTitle(alertsPage, L["Expiration Alerts"], -8)

controls.alertEnabledCheck = CreateCheckbox(
  alertsPage,
  "SeaCatEchoTrackerAlertEnabledCheck",
  L["Enable Expiration Alerts"],
  "TOP",
  alertsPage,
  "TOP",
  0,
  -34,
  function()
    return AlertIsEnabled()
  end,
  function(v)
    SeaCatEchoTrackerDB.alerts.enabled = v
    if not v then
      UpdateAlertState(false)
    end
  end
)

controls.alertThresholdSlider = CreateCenteredNumberSlider(
  "SeaCatEchoTrackerAlertThresholdSlider",
  alertsPage,
  L["Alert Threshold (seconds)"],
  -86,
  1,
  8,
  function()
    return SeaCatEchoTrackerDB.alerts.threshold or defaults.alerts.threshold
  end,
  function(v)
    SeaCatEchoTrackerDB.alerts.threshold = v
  end
)

local alertTextColorRow = CreateNestedColorRow(
  alertsPage,
  L["Alert Text Color"],
  -150,
  function()
    local c = EnsureAlertSettings().textColor
    return c[1], c[2], c[3]
  end,
  function(r, g, b)
    local c = EnsureAlertSettings().textColor
    c[1], c[2], c[3] = r, g, b
  end
)
styleWidgets.alertTextSwatch = alertTextColorRow.swatch

local alertGlowColorRow = CreateNestedColorRow(
  alertsPage,
  L["Glow Color"],
  -200,
  function()
    local c = EnsureAlertSettings().glowColor
    return c[1], c[2], c[3]
  end,
  function(r, g, b)
    local c = EnsureAlertSettings().glowColor
    c[1], c[2], c[3] = r, g, b
  end
)
styleWidgets.alertGlowSwatch = alertGlowColorRow.swatch

controls.alertGlowCheck = CreateCheckbox(
  alertsPage,
  "SeaCatEchoTrackerAlertGlowCheck",
  L["WeakAura-Style Glow"],
  "TOPLEFT",
  alertsPage,
  "TOPLEFT",
  54,
  -252,
  function()
    return SeaCatEchoTrackerDB.alerts.glow
  end,
  function(v)
    SeaCatEchoTrackerDB.alerts.glow = v
  end
)

controls.alertPulseCheck = CreateCheckbox(
  alertsPage,
  "SeaCatEchoTrackerAlertPulseCheck",
  L["Pulse Animation"],
  "TOPLEFT",
  alertsPage,
  "TOPLEFT",
  54,
  -286,
  function()
    return SeaCatEchoTrackerDB.alerts.pulse
  end,
  function(v)
    SeaCatEchoTrackerDB.alerts.pulse = v
  end
)

local alertsTabHelp = alertsPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
alertsTabHelp:SetPoint("TOP", 0, -334)
alertsTabHelp:SetWidth(300)
alertsTabHelp:SetJustifyH("CENTER")
alertsTabHelp:SetText(L["Sound options moved to the Sound tab for a cleaner layout."])
alertsTabHelp:SetTextColor(0.72, 0.72, 0.72)

CreateCenteredSectionTitle(soundPage, L["Alert Sound"], -8)

controls.alertSoundCheck = CreateCheckbox(
  soundPage,
  "SeaCatEchoTrackerAlertSoundCheck",
  L["Bell Toll Sound"],
  "TOPLEFT",
  soundPage,
  "TOPLEFT",
  54,
  -42,
  function()
    return SeaCatEchoTrackerDB.alerts.sound
  end,
  function(v)
    SeaCatEchoTrackerDB.alerts.sound = v
    if not v then
      alertState.soundPlayed = false
      alertState.repeatTimer = 0
    end
  end
)

controls.alertOncePerCastCheck = CreateCheckbox(
  soundPage,
  "SeaCatEchoTrackerAlertOncePerCastCheck",
  L["Only Play Once Per Alert Window"],
  "TOPLEFT",
  soundPage,
  "TOPLEFT",
  54,
  -76,
  function()
    return EnsureAlertSettings().oncePerCast
  end,
  function(v)
    EnsureAlertSettings().oncePerCast = v
    alertState.soundPlayed = false
    alertState.repeatTimer = 0
  end
)

controls.alertRepeatSlider = CreateCenteredNumberSlider(
  "SeaCatEchoTrackerAlertRepeatSlider",
  soundPage,
  L["Repeat Every (seconds)"],
  -138,
  1,
  5,
  function()
    return math.floor((EnsureAlertSettings().repeatSeconds or 1) + 0.5)
  end,
  function(v)
    EnsureAlertSettings().repeatSeconds = v
  end
)

local soundChannelLabel = soundPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
soundChannelLabel:SetPoint("TOP", 0, -196)
soundChannelLabel:SetText(L["Sound Channel"])

controls.alertSoundChannelDropdown = CreateFrame("Frame", "SeaCatEchoTrackerAlertSoundChannelDropdown", soundPage, "UIDropDownMenuTemplate")
controls.alertSoundChannelDropdown:ClearAllPoints()
controls.alertSoundChannelDropdown:SetPoint("TOP", 0, -212)
UIDropDownMenu_SetWidth(controls.alertSoundChannelDropdown, 120)

UIDropDownMenu_Initialize(controls.alertSoundChannelDropdown, function(self, level)
  local channels = {
    { text = L["Master"], value = "Master" },
    { text = L["SFX"], value = "SFX" },
    { text = L["Ambience"], value = "Ambience" },
    { text = L["Dialog"], value = "Dialog" },
    { text = L["Talking Head"], value = "TalkingHead" },
  }

  for _, info in ipairs(channels) do
    local entry = UIDropDownMenu_CreateInfo()
    entry.text = info.text
    entry.checked = (EnsureAlertSettings().soundChannel == info.value)
    entry.func = function()
      EnsureAlertSettings().soundChannel = info.value
      UIDropDownMenu_SetText(controls.alertSoundChannelDropdown, info.text)
      alertState.soundPlayed = false
      alertState.repeatTimer = 0
      if EnsureAlertSettings().sound then
        PlayAlertSound()
      end
    end
    UIDropDownMenu_AddButton(entry, level)
  end
end)

UIDropDownMenu_SetText(
  controls.alertSoundChannelDropdown,
  GetSoundChannelLabel(EnsureAlertSettings().soundChannel)
)

local soundNote = soundPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
soundNote:SetPoint("TOP", 0, -258)
soundNote:SetWidth(280)
soundNote:SetJustifyH("CENTER")
soundNote:SetText(L["Uses Bell Toll. Test it below and pick the channel you want."])
soundNote:SetTextColor(0.72, 0.72, 0.72)

local testSoundButton = CreateMenuButton(soundPage, "SeaCatEchoTrackerTestSoundButton", 120, 24, L["Test Sound"])
testSoundButton:ClearAllPoints()
testSoundButton:SetPoint("TOP", 0, -300)
testSoundButton:SetScript("OnClick", function()
  alertState.soundPlayed = false
  alertState.repeatTimer = 0
  PlayAlertSound()
end)

local resetButton = CreateMenuButton(panel, "SeaCatEchoTrackerResetDefaultsButton", 150, 26, L["Reset to Defaults"])
resetButton:SetPoint("BOTTOM", 0, 16)
resetButton:SetScript("OnClick", function()
  ResetToDefaults()
end)

SelectTab(SeaCatEchoTrackerDB.lastTab or "general")
ApplySettings()
RefreshControls()

minimapButton = CreateFrame("Button", "SeaCatEchoTrackerMinimapButton", Minimap)
minimapButton:SetSize(31, 31)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:EnableMouse(true)
minimapButton:RegisterForDrag("LeftButton")
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

minimapButton.border = minimapButton:CreateTexture(nil, "OVERLAY")
minimapButton.border:SetSize(53, 53)
minimapButton.border:SetPoint("TOPLEFT")
minimapButton.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

minimapButton.background = minimapButton:CreateTexture(nil, "BACKGROUND")
minimapButton.background:SetSize(20, 20)
minimapButton.background:SetPoint("CENTER", 0, 0)
minimapButton.background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

minimapButton.icon = minimapButton:CreateTexture(nil, "ARTWORK")
minimapButton.icon:SetSize(18, 18)
minimapButton.icon:SetPoint("CENTER", 0, 0)
minimapButton.icon:SetTexture(ECHO_ICON)
minimapButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

minimapButton:SetScript("OnDragStart", function(self)
  self:SetScript("OnUpdate", function()
    SeaCatEchoTrackerDB.minimap = CopyDefaults(defaults.minimap, SeaCatEchoTrackerDB.minimap)
    SeaCatEchoTrackerDB.minimap.angle = GetMinimapAngle()
    UpdateMinimapButtonPosition()
  end)
end)

minimapButton:SetScript("OnDragStop", function(self)
  self:SetScript("OnUpdate", nil)
end)

minimapButton:SetScript("OnClick", function(_, button)
  if button == "RightButton" then
    panel:Hide()
    return
  end

  if panel:IsShown() then
    panel:Hide()
  else
    panel:Show()
  end
end)

minimapButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(L["Echo Tracker"])
  GameTooltip:AddLine(L["Left Click: Open settings"], 1, 1, 1)
  GameTooltip:AddLine(L["Drag: Move minimap button"], 1, 1, 1)
  GameTooltip:AddLine(L["Right Click: Close settings"], 1, 1, 1)
  GameTooltip:Show()
end)

minimapButton:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

UpdateMinimapButtonPosition()

if SeaCatEchoTrackerDB.minimap.hide then
  minimapButton:Hide()
else
  minimapButton:Show()
end

-- ESC > Options > AddOns entry. The options panel is a standalone movable frame
-- so it can be dragged aside while previewing changes on the tracker, which the
-- settings canvas cannot do; the category therefore hosts a button that opens it
-- rather than reparenting the panel into the canvas.
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
  local host = CreateFrame("Frame")
  host.name = "SeaCat Echo Tracker"
  -- The settings canvas resizes this on display, but it starts at zero size and
  -- a zero-width parent would collapse the wrapped blurb below into nothing.
  host:SetSize(600, 400)

  local title = host:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(L["Echo Tracker"])

  local blurb = host:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  blurb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  blurb:SetPoint("RIGHT", host, "RIGHT", -16, 0)
  blurb:SetJustifyH("LEFT")
  blurb:SetText(L["Settings open in their own movable window, so you can drag them aside and watch the tracker update as you make changes."])

  local open = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
  open:SetSize(180, 24)
  open:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -16)
  open:SetText(L["Open Settings"])
  open:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel:IsShown() then
      HideUIPanel(SettingsPanel)
    end
    panel:Show()
  end)

  local category = Settings.RegisterCanvasLayoutCategory(host, host.name)
  category.ID = host.name
  Settings.RegisterAddOnCategory(category)
end

-- /et is kept for muscle memory from the original addon. If both are installed
-- the later one wins that alias, which is why /sce exists as the unambiguous one.
SLASH_SEACATECHOTRACKER1 = "/sce"
SLASH_SEACATECHOTRACKER2 = "/seacatecho"
SLASH_SEACATECHOTRACKER3 = "/seacatechotracker"
SLASH_SEACATECHOTRACKER4 = "/et"

SlashCmdList["SEACATECHOTRACKER"] = function(msg)
  msg = string.lower((msg or ""):match("^%s*(.-)%s*$") or "")

  if msg == "" then
    if panel:IsShown() then
      panel:Hide()
    else
      panel:Show()
    end
    return
  end

  if msg == "show" then
    frame:SetAlpha(1)
    SeaCatEchoTrackerDB.alwaysShow = true
    RefreshControls()
    ApplySettings()
    return
  end

  if msg == "hide" then
    SeaCatEchoTrackerDB.alwaysShow = false
    RefreshControls()
    ApplySettings()
    return
  end

  if msg == "unlock" then
    SeaCatEchoTrackerDB.unlocked = true
    if not panel:IsShown() then
      panel:Show()
    end
    RefreshControls()
    ApplySettings()
    return
  end

  if msg == "lock" then
    SeaCatEchoTrackerDB.unlocked = false
    RefreshControls()
    ApplySettings()
    return
  end

  if msg == "reset" then
    ResetToDefaults()
    return
  end

  -- Self-check for the hardcoded spell table. 1256581 in particular could not be
  -- verified against any public database, so the names have to be confirmed
  -- in-game rather than assumed correct.
  if msg == "spells" then
    local function describe(spellID)
      local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
      local name = info and info.name
      if name then
        return "|cff70C0F5" .. spellID .. "|r " .. name
      end
      return "|cffff5555" .. spellID .. "|r <" .. L["unknown spell"] .. ">"
    end

    local duration = ns.GetEchoDuration and ns.GetEchoDuration() or ECHO_DURATION_FALLBACK
    local calibrated = type(SeaCatEchoTrackerDB.echoDuration) == "number" and SeaCatEchoTrackerDB.echoDuration > 0

    print("|cff70C0F5SeaCat Echo Tracker|r " .. L["Echo duration"] .. ": " .. string.format("%.1f", duration)
      .. (calibrated and (" (" .. L["calibrated"] .. ")") or (" (" .. L["not yet calibrated"] .. ")")))

    print("|cff70C0F5SeaCat Echo Tracker|r " .. L["Applies Echo"] .. ":")
    for spellID in pairs(APPLY_SPELLS) do
      print("  " .. describe(spellID))
    end

    print("|cff70C0F5SeaCat Echo Tracker|r " .. L["Consumes Echo"] .. ":")
    for spellID, kind in pairs(CONSUME_SPELLS) do
      local suffix = ""
      if kind == "friendly" then
        suffix = "  (" .. L["friendly target only"] .. ")"
      end
      if EMPOWERED_SPELLS[spellID] then
        suffix = suffix .. "  (" .. L["empowered, settled on release"] .. ")"
      end
      print("  " .. describe(spellID) .. suffix)
    end

    print("|cff70C0F5SeaCat Echo Tracker|r " .. L["Grants an extra Echo target"] .. ":")
    print("  " .. describe(EMERALD_BLOSSOM_SPELL_ID)
      .. "  (" .. EXTRA_TARGET_MAX_STACKS .. " " .. L["stacks max"] .. ", "
      .. EXTRA_TARGET_DURATION .. "s)")
    return
  end

  -- Diagnostic for position problems: prints what is stored against where the
  -- frame actually sits, so a mismatch tells you whether the save or the restore
  -- is at fault.
  if msg == "pos" then
    local point, relativeTo, relativePoint, x, y = frame:GetPoint()
    print("|cff70C0F5SeaCat|r stored: " .. tostring(SeaCatEchoTrackerDB.point)
      .. " / " .. tostring(SeaCatEchoTrackerDB.relativePoint)
      .. " x=" .. tostring(SeaCatEchoTrackerDB.x)
      .. " y=" .. tostring(SeaCatEchoTrackerDB.y))
    print("|cff70C0F5SeaCat|r live:   " .. tostring(point)
      .. " / " .. tostring(relativePoint)
      .. " x=" .. tostring(x)
      .. " y=" .. tostring(y)
      .. " anchor=" .. tostring(relativeTo and relativeTo:GetName() or relativeTo))
    print("|cff70C0F5SeaCat|r scale:  frame=" .. tostring(frame:GetScale())
      .. " effective=" .. tostring(frame:GetEffectiveScale())
      .. " uiparent=" .. tostring(UIParent:GetScale())
      .. " points=" .. tostring(frame:GetNumPoints()))
    return
  end

  print("|cff70C0F5SeaCat Echo Tracker|r " .. L["commands:"])
  print("|cff70C0F5/sce|r - " .. L["toggle settings"])
  print("|cff70C0F5/sce show|r - " .. L["enable always show"])
  print("|cff70C0F5/sce hide|r - " .. L["disable always show"])
  print("|cff70C0F5/sce unlock|r - " .. L["unlock tracker frame"])
  print("|cff70C0F5/sce lock|r - " .. L["lock tracker frame"])
  print("|cff70C0F5/sce reset|r - " .. L["reset settings to defaults"])
  print("|cff70C0F5/sce spells|r - " .. L["show spell table self-check"])
  print("|cff70C0F5/seacatechotracker|r - " .. L["same as /sce, if you prefer the full name"])
  print("|cff70C0F5" .. L["Alerts"] .. "|r " .. L["Alerts are configurable in the Alerts tab."])
  print("|cff70C0F5" .. L["Echo Tracker"] .. "|r " .. L["Also reachable from ESC > Options > AddOns."])
end
local startupRefresh = CreateFrame("Frame")
startupRefresh:RegisterEvent("PLAYER_LOGIN")
startupRefresh:RegisterEvent("PLAYER_ENTERING_WORLD")

startupRefresh:SetScript("OnEvent", function(self, event)
  EnsureAlertSettings()

  if minimapButton then
    UpdateMinimapButtonPosition()
    if SeaCatEchoTrackerDB.minimap.hide then
      minimapButton:Hide()
    else
      minimapButton:Show()
    end
  end

  if panel then
    SelectTab(SeaCatEchoTrackerDB.lastTab or "general")
  end

  if RefreshControls then
    RefreshControls()
  end

  ApplySettings()

  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      if RefreshControls then
        RefreshControls()
      end
      ApplySettings()
    end)
  end

  if event == "PLAYER_ENTERING_WORLD" then
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
  end
end)

-- OnDragStop is the primary way the position is stored, but it only runs if the
-- drag ends cleanly on the frame. Capturing the live anchor at logout means what
-- you see when you reload is what you get back, whatever happened during the drag.
local positionSaver = CreateFrame("Frame")
positionSaver:RegisterEvent("PLAYER_LOGOUT")
positionSaver:SetScript("OnEvent", function()
  SaveFramePosition()
end)
