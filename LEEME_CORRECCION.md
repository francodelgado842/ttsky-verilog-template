# Corrección del test de compuertas EMG

## Causa encontrada
En el ZIP recibido, test/tb.v había sido sustituido por el wrapper local simplificado. No conectaba VPWR ni VGND. test/Makefile activa GL_TEST y USE_POWER_PINS para simular el netlist SKY130; por eso el circuito simulado requiere esos pines. El RTL no los necesita, lo que explica que el test RTL pase.

## Reemplazar en el repositorio (mismas rutas)
- test/tb.v: restaura el wrapper de la plantilla, con VPWR=1 y VGND=0 bajo GL_TEST y volcado de ondas.
- test/test.py: conserva todas las comprobaciones y los datos reales. Ajusta tick a 1 us (1 MHz: 250 ns bajo, 500 ns alto, 250 ns bajo) para dar margen a la propagación de las celdas. Añade un diagnóstico explícito de valores X/Z; NO los convierte artificialmente a cero.
- info.yaml: corrige descripción de sumador, reloj de uso previsto (1 MHz) y nombres de pines. Conserva top_module tt_um_example y tiles 1x1.

Mantener src/project.v, src/config.json, test/Makefile, test/requirements.txt, workflows y ambos .hex. No subir este paquete como subcarpeta; reemplazar los archivos dentro de las carpetas que ya existen. No hace falta instalar simuladores en Windows.

## GitHub
1. Confirmar los tres reemplazos en un nuevo commit.
2. Abrir Actions y revisar test y gds del NUEVO commit. Los workflows recibidos se disparan con push.
3. En gds comprobar gds, precheck y gl_test. Si se lanza manualmente, seleccionar la rama actual. Reejecutar la ejecución vieja usa el código viejo.
4. Si gl_test falla otra vez, enviar el primer AssertionError completo y el log de ese nuevo commit.

## Qué significan los resultados
Las capturas recibidas muestran gds y precheck aprobados, gl_test fallido, utilización reportada 67.242% y 1107 celdas excluyendo fill/tap. El fallo mostrado está en el entorno de simulación, no prueba un error de cálculo MAV.

El CLOCK_PERIOD de src/config.json sigue siendo 20 ns como en la plantilla recibida; es una restricción de implementación distinta del reloj de uso declarado en info.yaml. Esta corrección no cambia esa restricción ni determina la frecuencia máxima del silicio.

La prueba de conexión local usa un módulo de diagnóstico sensible a VPWR/VGND: reproduce X con el wrapper viejo y pasa con el corregido. Es una comprobación de cableado, NO una simulación del netlist real.
El ZIP recibido no contiene gate_level_netlist.v ni los resultados completos de temporización. El gl_test real queda pendiente de GitHub; no se declara aprobado ni listo para fabricación.

## Validación ejecutada
Icarus 11 + cocotb 2.1.0: PASS del test completo corregido, con 16000 muestras reales y 250 ventanas (125 por grabación). Reposo: 0 ventanas activas; cierre: 111. Se mantienen las pruebas de aritmética, protocolo, histéresis, configuración, snapshots y datos aleatorios. Esto verifica RTL; no sustituye el gl_test pendiente.
