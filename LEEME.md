# CI EMG MAV64 — versión RTL 1

Circuito digital de un canal: resta de offset, valor absoluto, MAV de 64 muestras y detector con histéresis. Entrada ADC de 12 bits sin signo (0..4095). Se reciben números, no voltajes analógicos. El ADC/adquisición sigue siendo externo.

## Estado comprobado

- Simulado con Icarus Verilog 11.0 y cocotb 2.0.1.
- Pruebas de protocolo, reset, habilitación, extremos, igualdad con umbrales, descarte de bloques parciales, datos inválidos, captura estable, 30 bloques pseudoaleatorios y muestras reales: PASS.
- Testbench autónomo: 16000 muestras reales, 250 ventanas; PASS.
- Reposo: 0/125 ventanas activas. Cierre: 111/125 ventanas activas.
- Resultado del par de demostración, NO precisión general ni validación clínica. El bloque etiquetado cierre contiene un inicio de poca amplitud; 14 ventanas no activas no significan necesariamente 14 errores de clasificación.

## Archivos

- src/project.v: código sintetizable, módulo tt_um_example para mantener el nombre de tu plantilla actual.
- test/tb_selfcheck.sv: testbench autónomo en SystemVerilog, sin Python.
- test/tb.v: envolvente para la simulación cocotb local.
- test/test.py: pruebas cocotb completas; sí simulan el Verilog.
- test/reposo_ch0.hex y test/cierre_ch0.hex: 8000 muestras CH0 cada uno, extraídas sin filtros ni escalado.
- run_sim.py: ejecutor cocotb local (requiere cocotb 2 y ejecutables Icarus en PATH).
- docs/info.md: documentación para tu repositorio Tiny Tapeout.
- docs/info_yaml_edits.txt: campos a actualizar en info.yaml, sin borrar las demás claves.
- test/mav_waveforms.vcd: captura de la simulación autónoma ejecutada aquí; se puede abrir en GTKWave.

## Ruta sencilla: testbench sin Python

Con Icarus Verilog instalado y accesible en PATH, abre una terminal en la carpeta test y ejecuta:

```bat
iverilog -g2012 -Wall -s tb_selfcheck -o sim_selfcheck ../src/project.v tb_selfcheck.sv
vvp sim_selfcheck +dump
```

Debe aparecer:

```text
PASS: 250 real windows, rest active=0/125, closure active=111/125
```

`+dump` genera mav_waveforms.vcd. Ejecuta `gtkwave mav_waveforms.vcd` si GTKWave está instalado.
Añade señales dut.centered, dut.magnitude, dut.mav y dut.activity. Configura centered como decimal con signo y las demás como decimal sin signo. La actividad se mantiene entre ventanas.

La simulación acelera las transferencias: el tiempo de pared/escala del VCD no representa una adquisición a 2 kHz. Las 64 muestras equivalen a 32 ms de señal adquirida a 2 kHz, aunque el TB las entregue más rápido.

## Ruta completa: cocotb + Verilog

```bat
python -m pip install cocotb==2.0.1
python run_sim.py
```

Requiere Icarus en PATH. PyCharm por sí solo no compila Verilog. run_sim.py usa Python para manejar un simulador HDL real. Las advertencias de Timer `units` en cocotb 2 son de compatibilidad, no errores; test.py conserva ese argumento para funcionar también en plantillas con cocotb 1.x. El ejecutor run_sim.py requiere cocotb 2.

## Integrar en tu plantilla Tiny Tapeout existente

1. Sustituye src/project.v por este archivo. Su módulo sigue llamándose tt_um_example.
2. Sustituye test/test.py y agrega los dos .hex dentro de test/.
3. Conserva tu Makefile, requirements.txt, config.json y workflows del template. Conserva también el tb.v original si expone clk, rst_n, ena, ui_in, uio_in, uo_out, uio_out y uio_oe; así mantienes sus condiciones para simulación de compuertas. El test no accede a registros internos.
4. Actualiza info.yaml con docs/info_yaml_edits.txt. Mantén top_module y source_files coherentes. No copies este fragmento encima de todo el archivo.
5. Copia docs/info.md a la misma ruta del repositorio.
6. Commit de código y pruebas juntos. Revisa primero el flujo test y después gds.

El reloj de 1 MHz del ejemplo es un objetivo inicial que debes verificar en STA, no una frecuencia máxima medida. A diferencia del sumador, este circuito sí necesita clk; clock_hz no debe permanecer en cero.

## Matemática exacta

Para cada muestra ADC, x = ADC - offset (resta de 13 bits con signo). abs(x) tiene 12 bits sin signo. Se suman exactamente 64 magnitudes en 18 bits: máximo 64*4095=262080. MAV=floor(suma/64). La muestra 64 se incluye antes de dividir. No hay ventanas solapadas.

MAV > high activa. MAV < low desactiva. Entre umbrales o en igualdad mantiene el estado. Los umbrales están en cuentas de magnitud, no en voltios. No se resta el nivel de ruido al MAV. No se aplica notch ni filtro pasa banda.

Valores al reset (demostración CH0, paciente_001, sesión 01, 4-junio-2026): offset=1995, low=10, high=16. Offset redondeado del reposo 0001. P95 del MAV64 de ese reposo es 7.8 cuentas; low=ceil(1.25*ceil(P95))=10 y high=2*ceil(P95)=16 dan márgenes iniciales sencillos. Son una regla de arranque, no una optimización validada.

En escala nominal 3.3/4096: low≈8.06 mV y high≈12.89 mV de componente AC al ADC. Con ganancia de adquisición 1000 V/V confirmada, equivalen nominalmente a 8.06 y 12.89 µV referidos al electrodo. Calibración del ADC y tolerancia de ganancia siguen afectando estas conversiones. El chip opera en cuentas, sin necesitar esa conversión.

MAV no truncado por grabación: reposo 5.62 mV, cierre 45.70 mV. El chip usa promedio entero por ventanas, por lo que estos promedios globales no son el valor de todas las ventanas. La auditoría halló variación de offset y reposo elevado en otras sesiones: recalibrar antes de usarlos. No cambiar las señales para forzar una separación.

## Pines, protocolo y observación

| Puerto | Sentido | Uso |
|---|---|---|
| ui_in[7:0] | Entrada | Byte de comando o dato |
| uo_out[7:0] | Salida | Byte de lectura |
| uio[0] | Entrada | WRITE |
| uio[1] | Entrada | CMD=1 comando; CMD=0 dato |
| uio[3:2] | Entrada | VIEW: 0 centrada, 1 rectificada, 2 MAV, 3 estado |
| uio[4] | Entrada | BYTE: 0 bajo, 1 alto |
| uio[5] | Salida | Actividad |
| uio[6] | Salida | RESULT_TOGGLE, cambia con cada MAV nuevo |
| uio[7] | Salida | ACK_TOGGLE, cambia por escritura capturada |
| clk | Entrada | Reloj de sistema |
| rst_n | Entrada | Reset síncrono activo en 0 |
| ena | Entrada | Habilitación de la infraestructura TT |

uio_oe=0xE0: los cinco bits inferiores reciben y los tres superiores conducen. Nunca conducir externamente uio[7:5]. Verificar niveles eléctricos en la placa real antes de conectar. Este bus requiere muchos GPIO; aún no hay pinout físico de una placa ESP32/XIAO confirmado.

### Escrituras

Todas las entradas deben ser síncronas al reloj. Estabiliza CMD y datos, lleva WRITE de 0 a 1 antes de un flanco ascendente de clk, mantén hasta después del flanco y vuelve a 0 durante al menos otro flanco. Un WRITE mantenido alto solo se acepta una vez. Si el host controla clk, cambia entradas con clk bajo. Esta versión no incluye sincronizadores para usar WRITE asíncrono respecto a un reloj libre; no conectar así sin adaptar el protocolo.

| Comando (CMD=1) | Bytes posteriores (CMD=0) | Efecto |
|---:|---|---|
| 0 | Bajo, alto | Recibir una muestra de 12 bits |
| 1 | Bajo, alto | Configurar offset |
| 2 | Bajo, alto | Configurar low |
| 3 | Bajo, alto | Configurar high |
| 4 | Ninguno | SNAPSHOT: capturar todas las etapas |
| 5 | Ninguno | Limpiar error |

El nibble superior del byte alto debe ser cero. Ejemplo muestra 2000=0x7D0: comando 0, byte 0xD0, byte 0x07, cada uno con su pulso WRITE. La muestra se procesa solo tras el byte alto.

Un comando nuevo cancela cualquier palabra incompleta. Comando desconocido, dato inesperado, valor superior a 4095 o umbrales que incumplan low<high activan error sin aceptar el valor. ACK confirma recepción, no validez. Configurar cada registro acepta/rechaza individualmente; no es actualización atómica de ambos umbrales. Para cambiar a cualquier par válido: high=4095 temporal, low=nuevo bajo y high=nuevo alto, sin intercalar muestras.

Cada cambio válido de offset/umbral descarta la ventana parcial, desactiva actividad y pone valid=0; conserva el último MAV hasta la siguiente ventana. Configurar entre grabaciones, no en medio de una contracción que se quiera evaluar.

### Lecturas

Envía comando 4 para congelar una copia consistente de centrada, rectificada, MAV y estado. Luego selecciona VIEW y BYTE para leer las dos mitades por uo_out. Las muestras pueden seguir llegando sin alterar esa copia. Otra orden 4 actualiza la copia.

Centrada: complemento a dos extendido a 16 bits. Rectificada/MAV: 12 bits, rellenados con ceros. Estado: bit0 actividad, bit1 MAV válido desde último reset/configuración, bit2 error; restantes cero. El error capturado requiere una nueva orden 4 para observarlo después de limpiarlo.

RESULT_TOGGLE evita depender de un pulso corto, pero no cuenta resultados: si el host deja pasar dos actualizaciones puede perderlas. Leer al menos una vez por ventana si se necesita cada resultado. No existe FIFO. Al detenerse las muestras se conserva el estado, no hay watchdog ni control de motores en esta versión.

## Próximo paso

Probar el flujo test de tu repositorio y generar GDS. Si excede área, la primera función que puede reducirse es la captura de depuración; no recortar resolución sin medir su efecto. Después preparar la conexión física del host elegido y validar umbrales en otras repeticiones.
