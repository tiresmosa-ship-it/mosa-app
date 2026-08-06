-- =====================================================================
-- MOSA TIRES - Limpieza total de datos de prueba (todas las pruebas de hoy,
-- tanto las tuyas manuales como las mias de verificacion de rotaciones/giro)
-- Ejecutar en: Supabase Dashboard > SQL Editor
--
-- Vacia TODA la actividad operacional (auditorias, cambios, checks diarios,
-- cierres, alertas, discrepancias, movimientos de bodega, intervenciones),
-- ya que el proyecto todavia no salio a produccion con mecanicos reales.
-- NO TOCA: usuarios, equipos, clientes, config_cliente, permisos, insumos,
-- proveedores.
-- =====================================================================

DELETE FROM cambio_detalle;
DELETE FROM movimientos_bodega;
DELETE FROM intervenciones;
DELETE FROM auditoria_posiciones;
DELETE FROM auditorias_receta;
DELETE FROM auditorias;
DELETE FROM cambios_neumaticos;
DELETE FROM alertas;
DELETE FROM discrepancias_inventario;
DELETE FROM check_diario_herramientas;
DELETE FROM check_diario;
DELETE FROM cierre_dia;

-- Neumaticos ficticios creados por las pruebas de hoy (no son inventario
-- real): los de rotacion/giro 6x4, y los de tus pruebas manuales.
DELETE FROM neumaticos WHERE numero_fuego IN (
  '99000001','99000002','99000003','99000010',
  '10830264','10830265','10830266','11229261','11111111',
  '30829261','429382413','316042601',
  '77000001','77000003','77000007',
  'TESTRETIRO001','TESTRETIRO002','TESTRETIRO003','TESTRETIRO004','TESTITEM9001',
  '900001','900002','900003','900004','900005','900006'
);

-- Proveedor de prueba usado para verificar el esquema de Maestros > Proveedores.
DELETE FROM proveedores WHERE id = '66666666-0001-0000-0000-000000000001';

-- Datos de prueba de Admin > Maestros (equipos/mecanicos/insumos no se tocan
-- en los DELETE de arriba, asi que se limpian puntualmente aca).
DELETE FROM equipos WHERE patente IN ('ZZ999TEST', 'DUPTEST');
DELETE FROM mecanicos WHERE usuario = 'testmec999';
DELETE FROM insumos WHERE id = '35af66aa-4a0b-4e77-9587-50e841bb930b';

-- Filas de prueba en usuarios (Maestros > Mecanicos ahora gestiona usuarios
-- en vez de la tabla legacy mecanicos): quedaron inactivas, se pueden borrar.
DELETE FROM usuarios WHERE usuario IN ('debugtest999', 'debugtest998', 'nuevotest999', 'verifytest001');

-- Herramientas de prueba usadas para verificar que el bloque 24 (RLS de
-- herramientas_inventario) quedo aplicado, mas la creada por la UI real.
DELETE FROM herramientas_inventario WHERE id = '66666666-0002-0000-0000-000000000002'
  OR nombre = 'Taladro Real Test';

-- Herramienta "Gata" (id 11111111-1111-1111-1111-111111111111) creada para
-- probar la comparacion de check diario vs herramientas_inventario (mejora
-- del check diario: discrepancias de herramientas). Su cantidad quedo en 5
-- tras probar el flujo de aprobacion (empezo en 3).
DELETE FROM herramientas_inventario WHERE id = '11111111-1111-1111-1111-111111111111';

-- Carga valorizada de neumaticos de prueba (lotes_inventario + neumaticos +
-- movimientos_bodega) usada para verificar el flujo completo end-to-end.
DELETE FROM lotes_inventario WHERE numero_documento LIKE 'DOC-NEU-TEST%' OR numero_documento LIKE 'DEBUGDOC%';
DELETE FROM neumaticos WHERE marca LIKE 'MarcaTest%' OR marca LIKE 'DebugLote%' OR marca = 'DebugNeu';

-- Neumatico de prueba usado para verificar el correlativo secuencial de
-- numero_fuego de BYS (Admin > Configuracion > Correlativos).
DELETE FROM neumaticos WHERE id_neumatico = '77777777-9999-0000-0000-000000000001';

-- Datos de prueba de superadmin.html (Clientes / Usuarios y permisos):
-- cliente de prueba "mosa_test_qa" (quedo desactivado tras probar el toggle
-- en cascada) y usuario mecanico "usuario_qa_test" creado para probar el
-- panel de permisos, junto con las filas de permisos que genero.
DELETE FROM permisos WHERE usuario_id IN (SELECT id FROM usuarios WHERE usuario = 'usuario_qa_test');
DELETE FROM usuarios WHERE usuario = 'usuario_qa_test';
DELETE FROM config_cliente WHERE cliente_id = 'mosa_test_qa';
DELETE FROM clientes WHERE id_cliente = 'mosa_test_qa';

-- Permisos de prueba generados al verificar el boton "Resetear permisos al
-- default del rol" contra el usuario real 'carlos' (mecanico, La Portada).
DELETE FROM permisos WHERE usuario_id = (SELECT id FROM usuarios WHERE usuario = 'carlos')
  AND seccion IN ('auditoria','hoja_cambio','cierre_dia','alertas_propias');

-- Usuario de prueba para verificar cliente-operativo.html (rol=cliente,
-- subtipo=operativo) contra la base real.
DELETE FROM usuarios WHERE usuario = 'clienteoperativo_test';

-- Movimiento de prueba para verificar la columna moneda (multi-moneda) en
-- Entrada de insumos. El insumo afectado (llanta americana_aluminio,
-- La Portada) ya se revirtio a mano a cantidad=0/precio=0 via REST, solo
-- falta borrar el movimiento (anon no tiene DELETE).
DELETE FROM movimientos_bodega WHERE numero_documento = 'TEST-MONEDA-1';

-- Usuarios de prueba para verificar cliente-gerencia.html (rol=cliente,
-- subtipo=dueno) y la creacion de operativos desde ese panel.
DELETE FROM usuarios WHERE usuario IN ('clientegerencia_test', 'operativo_prueba2_test');

-- Datos de demo cargados para mostrarle a Nelson el flujo completo (check
-- diario, 2 auditorias, hoja de cambio con foto, cierre, alertas) sobre
-- JFTH64 y JP2221. Las filas en cambio_detalle/intervenciones/auditoria_*
-- /cierre_dia/check_diario*/alertas ya quedan cubiertas por los DELETE
-- genericos del inicio de este archivo -- lo unico que NO cubren esos
-- DELETE es la tabla neumaticos, que se limpia aca puntualmente:
DELETE FROM neumaticos WHERE numero_fuego IN (
  '30829241','30829261','30829262','30829263','30829264','30829265','30829266',
  '41629261','41629262','41629263','41629264','41629265','41629266','41629267',
  '41629268','41629269','41629270','41629271','41629272','41629273'
);

-- Neumatico de prueba creado al verificar el fix de asegurarNeumatico (Bug 1:
-- auditoria con numero de fuego inexistente debia grabar tipo/estado/bodega
-- bien) contra NAK810. No se pudo borrar en el momento por REST (anon sin
-- DELETE en neumaticos).
DELETE FROM neumaticos WHERE numero_fuego LIKE 'AUDTEST%';

-- Filas de prueba insertadas al verificar db.registrarEventoSesion/Realtime
-- en vivo contra AE289ZB (anon sin DELETE en sesiones_trabajo).
DELETE FROM sesiones_trabajo WHERE id IN (
  '552c8f90-854a-4b7f-9401-9cc937365419',
  '9927e72a-78f8-4001-bf48-e90858c413f5',
  '007928fa-15e6-4f0f-9c80-726ea44ae007'
);

-- =====================================================================
-- Verificacion (deberia devolver 0 en todas)
-- =====================================================================
SELECT
  (SELECT count(*) FROM auditorias) AS auditorias,
  (SELECT count(*) FROM cambios_neumaticos) AS cambios,
  (SELECT count(*) FROM check_diario) AS checks,
  (SELECT count(*) FROM cierre_dia) AS cierres,
  (SELECT count(*) FROM alertas) AS alertas,
  (SELECT count(*) FROM intervenciones) AS intervenciones,
  (SELECT count(*) FROM movimientos_bodega) AS movimientos;

-- Prueba en vivo del flujo herramienta_nueva (catalogo dinamico de
-- herramientas + alerta + boton "Sumar a Catalogo" del Admin).
DELETE FROM herramientas_inventario WHERE nombre = 'Llave de impacto' AND cliente_id = 'la_portada';
DELETE FROM alertas WHERE tipo = 'herramienta_nueva' AND titulo = 'Nueva herramienta declarada en terreno';

-- Prueba en vivo del selector de medidas (config_cliente.medidas_permitidas
-- + alerta "Medida de neumático no estandarizada").
DELETE FROM alertas WHERE titulo = 'Medida de neumático no estandarizada';

-- Prueba en vivo del fix critico de tareas_diferidas + alerta hito_operativo.
DELETE FROM alertas WHERE id = '5bea83e6-986f-4534-b0de-300ef3bb6f53';
DELETE FROM sesiones_trabajo WHERE equipo_id = 'e4f35961-7d9b-4197-8c6a-1fab96b4d661' AND evento = 'HOJA_CAMBIO_EN_PROCESO' AND cambio_id IS NULL AND auditoria_id IS NULL;
DELETE FROM sesiones_trabajo WHERE auditoria_id = '2563a044-0eef-4ddb-ba7a-b0c5b763887d';

-- Prueba en vivo de EN_RECOMENDACIONES tras dropear sesiones_trabajo_evento_check
-- (la alerta hito_operativo asociada ya la borra el DELETE FROM alertas de arriba).
DELETE FROM sesiones_trabajo WHERE id = 'b7b9c43e-25cc-4272-93a8-b851bd1bf621';
DELETE FROM sesiones_trabajo WHERE id = 'ce61f7bf-796c-4232-ae19-cbeb34c55ddd';

-- Prueba en vivo del fix 4 (persistencia del log de movimientos): regulacion PSI de prueba en P4/AE289ZB.
DELETE FROM intervenciones WHERE id = 'b3ec4b87-1016-4b63-b9c9-758258ae0054';

-- Prueba en vivo del flujo completo Auditoria -> EN_RECOMENDACIONES -> Hoja de
-- Cambio en equipo AH771HG (119), para reproducir y confirmar el fix del bug
-- critico de enviarAuditoria (insert -> upsert, ver js/supabase.js). Incluye
-- una auditoria "de verdad" via construirYGuardarAuditoria/pushQueue (datos
-- de neumaticos de prueba: numero_fuego 1001-1010) y dos auditorias armadas a
-- mano para simular el escenario de reintento parcial.
DELETE FROM auditoria_posiciones WHERE auditoria_id IN ('ab4d80f7-d29a-4bc0-85a8-afbb7cb03310', '30d15bca-d686-4c2d-b7e8-6600955c9c91');
DELETE FROM auditorias_receta WHERE id = 'c1da6615-6f38-46fc-b78f-875e3e1fc71f';
DELETE FROM auditorias WHERE id_auditoria IN ('ab4d80f7-d29a-4bc0-85a8-afbb7cb03310', '30d15bca-d686-4c2d-b7e8-6600955c9c91');
DELETE FROM sesiones_trabajo WHERE equipo_id = 'e9f165c5-173a-489e-a732-c8629adad61f';
DELETE FROM neumaticos WHERE cliente_id = 'la_portada' AND numero_fuego IN ('1001','1002','1003','1004','1005','1006','1007','1008','1009','1010','2001','2002','2003');

-- Prueba en vivo con entrarDevHC (dev bypass): creo una auditoria/receta
-- vacia para AE289ZD (112) al probar el bypass ?dev=true sin querer.
DELETE FROM auditorias_receta WHERE id = 'e794940d-fc40-49a2-a4ae-31b85bd08fc2';
DELETE FROM auditorias WHERE id_auditoria = 'c8e03de5-1a8c-401b-a317-9b85af2df82b';
DELETE FROM sesiones_trabajo WHERE equipo_id = '0d6d06fd-a6d2-436a-b1ae-ce7a8919e7be';
DELETE FROM check_diario WHERE id = '65f79638-a268-49ed-b4e2-1362c959bc35';
