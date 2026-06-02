-- =================================================================
-- SHOPCORE — Script Completo de Base de Datos
-- Motor  : PostgreSQL 15+
-- Esquema: shopcore
-- Autor  : Equipo ShopCore | Base de Datos 2026
-- =================================================================


-- -----------------------------------------------------------------
-- ESQUEMA
-- -----------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS shopcore;
SET search_path TO shopcore;


-- =================================================================
-- SECCIÓN 1: CREACIÓN DE TABLAS
-- =================================================================

-- -----------------------------------------------------------------
-- TABLA: usuario
-- Almacena credenciales y nivel de acceso al sistema.
-- Es la tabla raíz del módulo de seguridad (RF-04).
-- -----------------------------------------------------------------
CREATE TABLE usuario (
    id_usuario  SERIAL       PRIMARY KEY,
    -- email es el identificador único de login (no puede repetirse)
    email       VARCHAR(150) UNIQUE NOT NULL,
    -- Se recomienda almacenar el hash (bcrypt) en producción
    contrasena  VARCHAR(255) NOT NULL,
    -- Tres roles posibles; CHECK garantiza integridad de dominio
    rol         VARCHAR(20)  NOT NULL
                CHECK (rol IN ('admin', 'cliente', 'bodeguero')),
    -- FALSE = cuenta desactivada (soft-delete, se conserva historial)
    activo      BOOLEAN      NOT NULL DEFAULT TRUE
);


-- -----------------------------------------------------------------
-- TABLA: cliente
-- Datos personales y dirección de envío del comprador.
-- La FK a usuario con UNIQUE garantiza cardinalidad 1:1.
-- -----------------------------------------------------------------
CREATE TABLE cliente (
    id_cliente     SERIAL       PRIMARY KEY,
    -- UNIQUE asegura que un usuario solo puede ser un cliente
    id_usuario     INT          UNIQUE NOT NULL
                   REFERENCES usuario(id_usuario) ON DELETE CASCADE,
    nombre         VARCHAR(100) NOT NULL,
    apellido       VARCHAR(100) NOT NULL,
    -- Email propio del cliente (puede ser distinto al de acceso)
    email          VARCHAR(150) UNIQUE NOT NULL,
    telefono       VARCHAR(20),                  -- Campo opcional
    direccion      VARCHAR(250),                 -- Dirección principal de envío
    fecha_registro DATE         NOT NULL DEFAULT CURRENT_DATE
);


-- -----------------------------------------------------------------
-- TABLA: categoria
-- Agrupa los productos en familias lógicas del catálogo.
-- ON DELETE RESTRICT evita eliminar categorías con productos.
-- -----------------------------------------------------------------
CREATE TABLE categoria (
    id_categoria SERIAL       PRIMARY KEY,
    nombre       VARCHAR(100) UNIQUE NOT NULL,   -- Nombre único de categoría
    descripcion  TEXT                            -- Puede ser NULL
);


-- -----------------------------------------------------------------
-- TABLA: producto
-- Catálogo de artículos disponibles para la venta.
-- stock_minimo activa alertas de reabastecimiento (RF-02).
-- -----------------------------------------------------------------
CREATE TABLE producto (
    id_producto  SERIAL        PRIMARY KEY,
    id_categoria INT           NOT NULL
                 REFERENCES categoria(id_categoria) ON DELETE RESTRICT,
    nombre       VARCHAR(150)  NOT NULL,
    descripcion  TEXT,
    -- Regla de negocio 4.1: precio siempre positivo
    precio       NUMERIC(10,2) NOT NULL CHECK (precio > 0),
    -- Regla de negocio 4.1: stock no puede ser negativo
    stock        INT           NOT NULL DEFAULT 0 CHECK (stock >= 0),
    -- Umbral para alertas de reposición (RF-02)
    stock_minimo INT           NOT NULL DEFAULT 5,
    -- Se actualiza automáticamente cuando stock llega a 0
    estado       VARCHAR(20)   NOT NULL DEFAULT 'disponible'
                 CHECK (estado IN ('disponible', 'agotado'))
);


-- -----------------------------------------------------------------
-- TABLA: pedido
-- Cabecera del pedido; los ítems residen en detalle_pedido.
-- subtotal, iva y total se calculan en registrar_pedido().
-- -----------------------------------------------------------------
CREATE TABLE pedido (
    id_pedido    SERIAL        PRIMARY KEY,
    -- RESTRICT: se conserva historial aunque el cliente sea inactivo
    id_cliente   INT           NOT NULL
                 REFERENCES cliente(id_cliente) ON DELETE RESTRICT,
    fecha_pedido TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- Ciclo de vida del pedido: pendiente → procesando → enviado → entregado
    estado       VARCHAR(20)   NOT NULL DEFAULT 'pendiente'
                 CHECK (estado IN ('pendiente','procesando',
                                   'enviado','entregado','cancelado')),
    subtotal     NUMERIC(10,2) NOT NULL DEFAULT 0,
    iva          NUMERIC(10,2) NOT NULL DEFAULT 0,  -- 19% calculado en el SP
    total        NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (total >= 0)
);


-- -----------------------------------------------------------------
-- TABLA: detalle_pedido
-- Resuelve la relación N:M entre PEDIDO y PRODUCTO.
-- precio_unitario captura el precio vigente al momento de la
-- compra, independiente de cambios futuros (Regla de negocio 4.3).
-- -----------------------------------------------------------------
CREATE TABLE detalle_pedido (
    id_detalle      SERIAL        PRIMARY KEY,
    -- CASCADE: si se borra el pedido, su detalle se borra también
    id_pedido       INT           NOT NULL
                    REFERENCES pedido(id_pedido) ON DELETE CASCADE,
    -- RESTRICT: no se borra un producto con historial de ventas
    id_producto     INT           NOT NULL
                    REFERENCES producto(id_producto) ON DELETE RESTRICT,
    cantidad        INT           NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(10,2) NOT NULL CHECK (precio_unitario > 0),
    -- Un producto no puede repetirse en la misma línea de pedido
    UNIQUE (id_pedido, id_producto)
);


-- -----------------------------------------------------------------
-- TABLA: pago
-- Registra la transacción financiera del pedido.
-- UNIQUE en id_pedido asegura cardinalidad 1:1 (Regla RN 4.4).
-- -----------------------------------------------------------------
CREATE TABLE pago (
    id_pago    SERIAL        PRIMARY KEY,
    -- UNIQUE garantiza 1 solo pago por pedido
    id_pedido  INT           UNIQUE NOT NULL
               REFERENCES pedido(id_pedido) ON DELETE RESTRICT,
    metodo     VARCHAR(30)   NOT NULL
               CHECK (metodo IN ('tarjeta','PSE','efectivo','nequi')),
    monto      NUMERIC(10,2) NOT NULL CHECK (monto > 0),
    fecha_pago TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado     VARCHAR(20)   NOT NULL DEFAULT 'pendiente'
               CHECK (estado IN ('pendiente','aprobado','fallido'))
);


-- =================================================================
-- SECCIÓN 2: INSERCIÓN DE REGISTROS DE PRUEBA
-- Propósito: validar integridad referencial y lógica de negocio
-- =================================================================

-- Usuarios del sistema (admin, 2 clientes y 1 bodeguero)
INSERT INTO usuario (email, contrasena, rol) VALUES
    ('admin@shopcore.com',    'admin123',    'admin'),
    ('juan.perez@email.com',  'cliente123',  'cliente'),
    ('maria.gomez@email.com', 'cliente456',  'cliente'),
    ('bodega@shopcore.com',   'bodega123',   'bodeguero');

-- Clientes vinculados a los usuarios con id_usuario 2 y 3
INSERT INTO cliente (id_usuario, nombre, apellido, email, telefono, direccion) VALUES
    (2, 'Juan',  'Perez', 'juan.perez@email.com',  '3001234567', 'Calle 80 #15-20, Bogota'),
    (3, 'Maria', 'Gomez', 'maria.gomez@email.com', '3109876543', 'Carrera 7 #45-10, Bogota');

-- Cuatro categorías de producto para el catálogo
INSERT INTO categoria (nombre, descripcion) VALUES
    ('Electronica', 'Dispositivos y accesorios electronicos'),
    ('Ropa',        'Prendas de vestir para adultos'),
    ('Hogar',       'Articulos para el hogar y decoracion'),
    ('Deportes',    'Equipos y accesorios deportivos');

-- Cinco productos del catálogo con stock inicial
INSERT INTO producto (id_categoria, nombre, precio, stock, stock_minimo) VALUES
    (1, 'Audifonos Bluetooth',     89900, 50, 10),
    (1, 'Cargador USB-C 65W',      45000, 80, 15),
    (2, 'Camiseta Polo',           35000,120, 20),
    (3, 'Lampara LED Escritorio',  62000, 30,  5),
    (4, 'Balon de Futbol',         55000, 15,  5);

-- Pedido de Juan Perez: 1 audifono con IVA del 19%
-- subtotal=89900  |  iva=17081  |  total=106981
INSERT INTO pedido (id_cliente, estado, subtotal, iva, total) VALUES
    (1, 'pendiente', 89900, 17081, 106981);

-- Línea de detalle: 1 unidad del producto 1 al precio vigente
INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario) VALUES
    (1, 1, 1, 89900);

-- Pago aprobado con tarjeta por el monto exacto del pedido
INSERT INTO pago (id_pedido, metodo, monto, estado) VALUES
    (1, 'tarjeta', 106981, 'aprobado');


-- =================================================================
-- SECCIÓN 3: CONSULTAS SQL
-- =================================================================

-- -----------------------------------------------------------------
-- CONSULTAS BÁSICAS
-- -----------------------------------------------------------------

-- Q1: Catálogo visible para el cliente (solo estado 'disponible')
-- Requerimiento: RF-01
SELECT nombre,
       precio,
       stock
FROM   producto
WHERE  estado = 'disponible';  -- Filtra productos agotados


-- Q2: Directorio de clientes para administración
SELECT nombre,
       apellido,
       email,
       telefono
FROM   cliente;


-- Q3: Bandeja de trabajo para el equipo de operaciones
-- Solo se muestran pedidos en estado inicial 'pendiente'
SELECT id_pedido,
       id_cliente,
       fecha_pedido,
       total
FROM   pedido
WHERE  estado = 'pendiente';


-- Q4: Alerta de inventario — stock por debajo del umbral mínimo
-- Requerimiento: RF-02 (alerta de reabastecimiento)
SELECT nombre,
       stock,
       stock_minimo,
       stock_minimo - stock AS unidades_faltantes  -- Cuántas faltan para llegar al mínimo
FROM   producto
WHERE  stock < stock_minimo
ORDER  BY unidades_faltantes DESC;  -- Más críticos primero


-- Q5: Reporte financiero de pagos confirmados
SELECT id_pago,
       id_pedido,
       metodo,
       monto
FROM   pago
WHERE  estado = 'aprobado'   -- Solo transacciones exitosas
ORDER  BY monto DESC;        -- Transacciones de mayor valor al inicio


-- -----------------------------------------------------------------
-- CONSULTAS INTERMEDIAS CON JOIN
-- -----------------------------------------------------------------

-- Q6: Vista de pedidos humanizada para soporte al cliente
-- INNER JOIN: solo pedidos que tienen un cliente asociado
SELECT p.id_pedido,
       c.nombre || ' ' || c.apellido AS cliente,  -- Nombre completo concatenado
       p.fecha_pedido,
       p.estado,
       p.total
FROM   pedido  p
JOIN   cliente c ON p.id_cliente = c.id_cliente;


-- Q7: Desglose línea a línea de todos los pedidos
-- Tres JOINs encadenados: detalle → pedido → cliente y producto
SELECT dp.id_pedido,
       c.nombre  || ' ' || c.apellido AS cliente,
       pr.nombre                      AS producto,
       dp.cantidad,
       dp.precio_unitario,
       -- Subtotal por línea (cantidad × precio capturado en el momento de la compra)
       dp.cantidad * dp.precio_unitario AS subtotal_linea
FROM   detalle_pedido dp
JOIN   pedido      p  ON dp.id_pedido   = p.id_pedido
JOIN   cliente     c  ON p.id_cliente   = c.id_cliente
JOIN   producto    pr ON dp.id_producto = pr.id_producto;


-- Q8: Conciliación de pedidos vs. pagos para el área financiera
SELECT p.id_pedido,
       c.nombre || ' ' || c.apellido AS cliente,
       p.total,
       pa.metodo,
       pa.estado AS estado_pago  -- Permite detectar pagos pendientes o fallidos
FROM   pedido  p
JOIN   cliente c  ON p.id_cliente = c.id_cliente
JOIN   pago    pa ON p.id_pedido  = pa.id_pedido;


-- Q9: Catálogo navegable organizado por categoría
SELECT pr.nombre  AS producto,
       cat.nombre AS categoria,
       pr.precio,
       pr.stock
FROM   producto  pr
JOIN   categoria cat ON pr.id_categoria = cat.id_categoria
ORDER  BY cat.nombre, pr.nombre;  -- Orden alfabético por categoría y luego por producto


-- -----------------------------------------------------------------
-- CONSULTAS AVANZADAS CON CTEs Y SUBCONSULTAS
-- -----------------------------------------------------------------

-- Q10: Ranking de clientes por valor de compras entregadas
-- CTE 'gastos_cliente': agrupa y suma antes de ordenar
WITH gastos_cliente AS (
    SELECT c.id_cliente,
           c.nombre || ' ' || c.apellido AS cliente,
           SUM(p.total)                  AS total_gastado
    FROM   pedido  p
    JOIN   cliente c ON p.id_cliente = c.id_cliente
    WHERE  p.estado = 'entregado'  -- Solo compras completadas (excluye cancelados)
    GROUP  BY c.id_cliente, c.nombre, c.apellido
)
SELECT cliente,
       total_gastado
FROM   gastos_cliente
ORDER  BY total_gastado DESC;  -- Mejores clientes primero


-- Q11: Inventario sin rotación — candidatos a descuento o retiro del catálogo
-- Subconsulta en NOT IN: obtiene todos los id_producto que aparecen en algún pedido
SELECT nombre,
       precio,
       stock
FROM   producto
WHERE  id_producto NOT IN (
    SELECT DISTINCT id_producto   -- DISTINCT evita duplicados en la subconsulta
    FROM   detalle_pedido
);


-- Q12: Segmento premium — clientes cuyo gasto supera el promedio del sistema
-- Primera CTE: total acumulado por cliente (sin cancelados)
WITH totales AS (
    SELECT id_cliente,
           SUM(total) AS total_cliente
    FROM   pedido
    WHERE  estado <> 'cancelado'  -- Excluye pedidos anulados del cálculo
    GROUP  BY id_cliente
)
SELECT c.nombre || ' ' || c.apellido AS cliente,
       t.total_cliente
FROM   totales  t
JOIN   cliente  c ON t.id_cliente = c.id_cliente
-- Subconsulta escalar: calcula el promedio sobre la CTE ya filtrada
WHERE  t.total_cliente > (SELECT AVG(total_cliente) FROM totales)
ORDER  BY t.total_cliente DESC;


-- Q13: Categoría con mayor inventario disponible
-- Útil para decisiones de compra y gestión de bodega
SELECT cat.nombre    AS categoria,
       SUM(pr.stock) AS stock_total  -- Suma del stock de todos los productos de la categoría
FROM   producto  pr
JOIN   categoria cat ON pr.id_categoria = cat.id_categoria
GROUP  BY cat.nombre
ORDER  BY stock_total DESC
LIMIT  1;  -- Solo la categoría con mayor inventario


-- =================================================================
-- SECCIÓN 4: FUNCIONES
-- =================================================================

-- -----------------------------------------------------------------
-- Función: calcular_total_con_iva
-- Parámetro : p_subtotal — valor base antes de impuestos
-- Retorna   : total con IVA del 19%, redondeado a 2 decimales
-- Uso       : SELECT calcular_total_con_iva(185000); → 220150.00
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION calcular_total_con_iva(p_subtotal NUMERIC)
RETURNS NUMERIC
LANGUAGE plpgsql AS $$
BEGIN
    -- Multiplica por 1.19 (equivale a sumar el 19% de IVA colombiano)
    RETURN ROUND(p_subtotal * 1.19, 2);
END;
$$;


-- -----------------------------------------------------------------
-- Función: obtener_stock
-- Parámetro : p_id_producto — identificador del producto a consultar
-- Retorna   : stock actual (INT) o -1 si el producto no existe
-- Uso       : SELECT obtener_stock(1);
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION obtener_stock(p_id_producto INT)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    v_stock INT;  -- Variable para capturar el resultado de la consulta
BEGIN
    SELECT stock INTO v_stock
    FROM   producto
    WHERE  id_producto = p_id_producto;

    -- NOT FOUND se activa si la consulta no retorna filas
    IF NOT FOUND THEN
        RETURN -1;  -- Centinela: producto inexistente
    END IF;

    RETURN v_stock;
END;
$$;


-- =================================================================
-- SECCIÓN 5: PROCEDIMIENTOS ALMACENADOS
-- =================================================================

-- -----------------------------------------------------------------
-- Procedimiento: registrar_pedido
-- Parámetros: p_id_cliente   — cliente que realiza la compra
--             p_id_producto  — producto a comprar
--             p_cantidad     — unidades solicitadas
-- Lanza EXCEPTION si stock < cantidad solicitada (Regla RN 4.3)
-- Uso: CALL registrar_pedido(1, 2, 3);
-- -----------------------------------------------------------------
CREATE OR REPLACE PROCEDURE registrar_pedido(
    p_id_cliente  INT,
    p_id_producto INT,
    p_cantidad    INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_precio    NUMERIC(10,2);  -- Precio vigente al momento de la compra
    v_stock     INT;            -- Stock disponible antes de la transacción
    v_subtotal  NUMERIC(10,2);
    v_iva       NUMERIC(10,2);
    v_total     NUMERIC(10,2);
    v_id_pedido INT;            -- ID generado por el INSERT en pedido
BEGIN
    -- 1. Obtener precio y stock actuales del producto
    SELECT precio, stock INTO v_precio, v_stock
    FROM   producto
    WHERE  id_producto = p_id_producto;

    -- 2. Validar disponibilidad antes de proceder (evita stock negativo)
    IF v_stock < p_cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente. Disponible: %', v_stock;
    END IF;

    -- 3. Calcular valores financieros del pedido
    v_subtotal := v_precio * p_cantidad;
    v_iva      := ROUND(v_subtotal * 0.19, 2);  -- IVA 19% (RF-06)
    v_total    := v_subtotal + v_iva;

    -- 4. Insertar cabecera del pedido y capturar su ID generado
    INSERT INTO pedido (id_cliente, estado, subtotal, iva, total)
    VALUES (p_id_cliente, 'pendiente', v_subtotal, v_iva, v_total)
    RETURNING id_pedido INTO v_id_pedido;

    -- 5. Insertar línea de detalle con el precio vigente (snapshot)
    INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario)
    VALUES (v_id_pedido, p_id_producto, p_cantidad, v_precio);

    -- 6. Descontar stock del producto (nunca queda negativo gracias al CHECK)
    UPDATE producto
    SET    stock = stock - p_cantidad
    WHERE  id_producto = p_id_producto;
END;
$$;


-- -----------------------------------------------------------------
-- Procedimiento: cancelar_pedido
-- Parámetro: p_id_pedido — identificador del pedido a cancelar
-- Lanza EXCEPTION si el pedido no existe o ya está en estado final
-- Uso: CALL cancelar_pedido(3);
-- -----------------------------------------------------------------
CREATE OR REPLACE PROCEDURE cancelar_pedido(p_id_pedido INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_estado VARCHAR(20);  -- Estado actual del pedido
    rec      RECORD;       -- Registro para iterar líneas de detalle
BEGIN
    -- 1. Verificar que el pedido existe
    SELECT estado INTO v_estado
    FROM   pedido
    WHERE  id_pedido = p_id_pedido;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El pedido % no existe.', p_id_pedido;
    END IF;

    -- 2. Validar que el estado permite cancelación (Regla RN 4.3)
    IF v_estado IN ('cancelado', 'entregado') THEN
        RAISE EXCEPTION 'Estado ''%'' no permite cancelacion.', v_estado;
    END IF;

    -- 3. Recorrer cada línea del pedido y restaurar el stock
    FOR rec IN
        SELECT id_producto, cantidad
        FROM   detalle_pedido
        WHERE  id_pedido = p_id_pedido
    LOOP
        -- Devolver las unidades al inventario disponible
        UPDATE producto
        SET    stock = stock + rec.cantidad
        WHERE  id_producto = rec.id_producto;
    END LOOP;

    -- 4. Marcar el pedido como cancelado en la cabecera
    UPDATE pedido
    SET    estado = 'cancelado'
    WHERE  id_pedido = p_id_pedido;
END;
$$;


-- =================================================================
-- SECCIÓN 6: TRIGGERS Y AUDITORÍA
-- =================================================================

-- -----------------------------------------------------------------
-- Tabla de auditoría (RF-09)
-- Registra QUIÉN hizo QUÉ, CUÁNDO y sobre QUÉ datos
-- -----------------------------------------------------------------
CREATE TABLE auditoria (
    id_auditoria  SERIAL       PRIMARY KEY,
    tabla         VARCHAR(50)  NOT NULL,                -- Tabla afectada (pedido / pago)
    operacion     VARCHAR(10)  NOT NULL,                -- INSERT | UPDATE | DELETE
    usuario_db    VARCHAR(100) NOT NULL DEFAULT current_user,  -- Usuario de BD activo
    fecha         TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    datos_antes   TEXT,   -- Estado anterior en JSON (NULL en INSERT)
    datos_despues TEXT    -- Estado posterior en JSON (NULL en DELETE)
);


-- -----------------------------------------------------------------
-- Función disparada por los triggers; usa variables especiales:
-- TG_TABLE_NAME : nombre de la tabla que disparó el trigger
-- TG_OP         : operación que ocurrió (INSERT / UPDATE / DELETE)
-- OLD           : fila anterior al cambio (NULL en INSERT)
-- NEW           : fila nueva después del cambio (NULL en DELETE)
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_auditoria()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO auditoria (tabla, operacion, datos_antes, datos_despues)
    VALUES (
        TG_TABLE_NAME,
        TG_OP,
        -- En INSERT no hay fila anterior; en UPDATE/DELETE se serializa OLD
        CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE row_to_json(OLD)::TEXT END,
        -- En DELETE no hay fila nueva; en INSERT/UPDATE se serializa NEW
        CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE row_to_json(NEW)::TEXT END
    );
    RETURN NEW;  -- Obligatorio en triggers AFTER; el valor no afecta la operación
END;
$$;


-- Trigger sobre PEDIDO: audita cualquier modificación al ciclo de vida del pedido
CREATE TRIGGER trg_auditoria_pedido
AFTER INSERT OR UPDATE OR DELETE ON pedido
FOR EACH ROW  -- Se ejecuta una vez por fila afectada
EXECUTE FUNCTION fn_auditoria();

-- Trigger sobre PAGO: audita cambios en transacciones financieras (RNF-02)
CREATE TRIGGER trg_auditoria_pago
AFTER INSERT OR UPDATE OR DELETE ON pago
FOR EACH ROW
EXECUTE FUNCTION fn_auditoria();


-- =================================================================
-- SECCIÓN 7: ROLES Y PERMISOS DE ACCESO
-- =================================================================

-- admin_rol: control total sobre todas las tablas del esquema
CREATE ROLE admin_rol;
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA shopcore TO admin_rol;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA shopcore TO admin_rol;
-- Las secuencias (SERIAL) deben incluirse para que los INSERT funcionen

-- cliente_rol: acceso de solo lectura al catálogo; puede crear sus pedidos y pagos
CREATE ROLE cliente_rol;
GRANT SELECT         ON producto, categoria          TO cliente_rol;
GRANT SELECT, INSERT ON pedido, detalle_pedido, pago TO cliente_rol;
GRANT SELECT         ON cliente                      TO cliente_rol;
-- Nota: el filtro por id_cliente se implementa en la capa de aplicación

-- bodega_rol: puede ver y actualizar inventario, consultar pedidos
-- No tiene acceso a datos financieros ni de clientes (principio de mínimo privilegio)
CREATE ROLE bodega_rol;
GRANT SELECT, UPDATE ON producto               TO bodega_rol;
GRANT SELECT         ON categoria              TO bodega_rol;
GRANT SELECT         ON pedido, detalle_pedido TO bodega_rol;
-- Sin acceso a: cliente, pago, auditoria, facturacion


-- =================================================================
-- FIN DEL SCRIPT — ShopCore 2026
-- =================================================================
