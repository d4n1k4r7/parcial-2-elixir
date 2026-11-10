defmodule Ciudad do
  defstruct [:id, :nombre, :habitantes]
end

defmodule Movimiento do
  defstruct [:codigo, :id_ciudad, :hora_inicio, :hora_final, :magnitud, :profundidad]
end

defmodule Validador do
  def parse_hora(str) do
    case Time.from_iso8601(str) do
      {:ok, time} -> {:ok, time}
      _ -> :error
    end
  end

  def parse_float(str) do
    case Float.parse(str) do
      {num, ""} -> {:ok, num}
      _ -> :error
    end
  end

  def parse_int(str) do
    case Integer.parse(str) do
      {num, ""} -> {:ok, num}
      _ -> :error
    end
  end
end

defmodule Lector do
  def leer_ciudades(ruta, parent_pid) do
    case File.read(ruta) do
      {:ok, contenido} ->
        lineas = String.split(contenido, ["\r\n", "\n"], trim: false)
        {ciudades, rechazados} = procesar_lineas_ciudades(lineas, [], 0)
        send(parent_pid, {:ciudades, {:ok, ciudades, rechazados}})

      {:error, _razon} ->
        send(parent_pid, {:ciudades, {:error, ruta}})
    end
  end

  defp procesar_lineas_ciudades([], acc, rechazos), do: {Enum.reverse(acc), rechazos}
  defp procesar_lineas_ciudades([linea | resto], acc, rechazos) do
    linea_limpia = String.trim(linea)

    if linea_limpia == "" do
      procesar_lineas_ciudades(resto, acc, rechazos)
    else
      partes = String.split(linea_limpia, "@")

      case partes do
        [id, nombre, hab_str] when id != "" and nombre != "" and hab_str != "" ->
          case Validador.parse_int(hab_str) do
            {:ok, hab} when hab > 0 ->
              ciudad = %Ciudad{id: id, nombre: nombre, habitantes: hab}
              procesar_lineas_ciudades(resto, [ciudad | acc], rechazos)

            _ ->
              procesar_lineas_ciudades(resto, acc, rechazos + 1)
          end

        _ ->
          procesar_lineas_ciudades(resto, acc, rechazos + 1)
      end
    end
  end

  def leer_movimientos(ruta, parent_pid) do
    case File.read(ruta) do
      {:ok, contenido} ->
        lineas = String.split(contenido, ["\r\n", "\n"], trim: false)
        {movimientos, rechazados} = procesar_lineas_movimientos(lineas, [], 0)
        send(parent_pid, {:movimientos, {:ok, movimientos, rechazados}})

      {:error, _razon} ->
        send(parent_pid, {:movimientos, {:error, ruta}})
    end
  end

  defp procesar_lineas_movimientos([], acc, rechazos), do: {Enum.reverse(acc), rechazos}
  defp procesar_lineas_movimientos([linea | resto], acc, rechazos) do
    linea_limpia = String.trim(linea)

    if linea_limpia == "" do
      procesar_lineas_movimientos(resto, acc, rechazos)
    else
      partes = String.split(linea_limpia, "@")

      case partes do
        [cod, id_c, h_ini, h_fin, mag, prof]
        when cod != "" and id_c != "" and h_ini != "" and h_fin != "" and mag != "" and prof != "" ->
          with {:ok, hora_i} <- Validador.parse_hora(h_ini),
               {:ok, hora_f} <- Validador.parse_hora(h_fin),
               {:ok, magnitud} <- Validador.parse_float(mag),
               {:ok, profundidad} when profundidad >= 0.0 <- Validador.parse_float(prof) do
            mov = %Movimiento{
              codigo: cod,
              id_ciudad: id_c,
              hora_inicio: hora_i,
              hora_final: hora_f,
              magnitud: magnitud,
              profundidad: profundidad
            }
            procesar_lineas_movimientos(resto, [mov | acc], rechazos)
          else
            _ -> procesar_lineas_movimientos(resto, acc, rechazos + 1)
          end

        _ ->
          procesar_lineas_movimientos(resto, acc, rechazos + 1)
      end
    end
  end
end

defmodule Calculador do
  def conciliar_movimientos(movimientos, ciudades) do
    ids_ciudades = MapSet.new(Enum.map(ciudades, & &1.id))
    separar_validos(movimientos, ids_ciudades, [], 0)
  end

  defp separar_validos([], _ids, validos_acc, rechazos_acc) do
    {Enum.reverse(validos_acc), rechazos_acc}
  end

  defp separar_validos([mov | resto], ids, validos_acc, rechazos_acc) do
    if MapSet.member?(ids, mov.id_ciudad) do
      separar_validos(resto, ids, [mov | validos_acc], rechazos_acc)
    else
      separar_validos(resto, ids, validos_acc, rechazos_acc + 1)
    end
  end

  def estadisticas_ciudad(movimientos_ciudad) do
    recorrer_movimientos(movimientos_ciudad, 0, nil, 0.0)
  end

  defp recorrer_movimientos([], 0, nil, _suma) do
    {:sin_movimientos, 0, "No aplica", "No aplica"}
  end

  defp recorrer_movimientos([], total, %Movimiento{codigo: cod, magnitud: mag}, suma_prof) do
    promedio = Float.round(suma_prof / total, 2)
    prom_str = :erlang.float_to_binary(promedio, decimals: 2) <> " km"
    max_str = "#{cod} #{mag}"
    {:con_movimientos, total, max_str, prom_str}
  end

  defp recorrer_movimientos([m | resto], 0, nil, _suma) do
    recorrer_movimientos(resto, 1, m, m.profundidad)
  end

  defp recorrer_movimientos([m | resto], total, max_actual, suma) do
    nuevo_max = if m.magnitud > max_actual.magnitud, do: m, else: max_actual
    recorrer_movimientos(resto, total + 1, nuevo_max, suma + m.profundidad)
  end
end

defmodule Reporte do
  def generar_texto(ciudades, movimientos, rech_ciudades, rech_movimientos) do
    {movs_validos, rech_id_invalido} = Calculador.conciliar_movimientos(movimientos, ciudades)
    total_rech_mov = rech_movimientos + rech_id_invalido

    cuerpo =
      Enum.map_join(ciudades, "\n", fn ciudad ->
        movs_ciudad = Enum.filter(movs_validos, &(&1.id_ciudad == ciudad.id))
        {estado, total, max_str, prom_str} = Calculador.estadisticas_ciudad(movs_ciudad)

        detalle_movs =
          if estado == :sin_movimientos do
            "  Sin movimientos registrados\n"
          else
            Enum.map_join(movs_ciudad, "\n", fn m ->
              "  - [#{m.codigo}] #{m.hora_inicio} -> #{m.hora_final} | Magnitud: #{m.magnitud} | Profundidad: #{m.profundidad} km"
            end) <> "\n"
          end

        """
        Ciudad: #{ciudad.nombre} (ID: #{ciudad.id})
        Número de habitantes: #{ciudad.habitantes}
        Movimientos registrados:
        #{detalle_movs}  Cantidad total de movimientos: #{total}
          Movimiento de mayor magnitud: #{max_str}
          Profundidad promedio: #{prom_str}
        ------------------------------------------------------------
        """
      end)

    resumen = """
    ============================================================
    REGISTROS RECHAZADOS:
      - Archivo resources/ciudades.txt: #{rech_ciudades}
      - Archivo resources/movimientos.txt: #{total_rech_mov}
    ============================================================
    """

    cuerpo <> resumen
  end
end

defmodule ServidorSismos do
  def start do
    case Process.whereis(:servicio_sismos) do
      nil ->
        pid = spawn(fn -> loop() end)
        Process.register(pid, :servicio_sismos)
        IO.puts("Servidor activo en el nodo: #{node()}")
        IO.puts("Proceso registrado como :servicio_sismos\n")

      _ ->
        IO.puts("El proceso :servicio_sismos ya se encuentra registrado.")
    end
  end

  defp loop do
    receive do
      {destino_respuesta, {:reporte_ciudad, id_ciudad}} ->
        respuesta = responder_reporte_ciudad(id_ciudad)
        send(destino_respuesta, respuesta)
        loop()

      {destino_respuesta, :reporte_general} ->
        respuesta = responder_reporte_general()
        send(destino_respuesta, respuesta)
        loop()

      {destino_respuesta, :fin} ->
        send(destino_respuesta, :fin)
        loop()
    end
  end

  defp leer_archivos_concurrente do
    parent = self()
    spawn(fn -> Lector.leer_ciudades("resources/ciudades.txt", parent) end)
    spawn(fn -> Lector.leer_movimientos("resources/movimientos.txt", parent) end)
    esperar_lecturas(nil, nil)
  end

  defp esperar_lecturas(res_c, res_m) when not is_nil(res_c) and not is_nil(res_m), do: {res_c, res_m}
  defp esperar_lecturas(res_c, res_m) do
    receive do
      {:ciudades, res} -> esperar_lecturas(res, res_m)
      {:movimientos, res} -> esperar_lecturas(res_c, res)
    end
  end

  defp responder_reporte_general do
    case leer_archivos_concurrente() do
      {{:ok, ciudades, rech_c}, {:ok, movimientos, rech_m}} ->
        Reporte.generar_texto(ciudades, movimientos, rech_c, rech_m)

      {{:error, ruta}, _} ->
        "Error: No se pudo leer el archivo #{ruta}"

      {_, {:error, ruta}} ->
        "Error: No se pudo leer el archivo #{ruta}"
    end
  end

  defp responder_reporte_ciudad(id_buscado) do
    case leer_archivos_concurrente() do
      {{:ok, ciudades, _rech_c}, {:ok, movimientos, _rech_m}} ->
        case Enum.find(ciudades, &(&1.id == id_buscado)) do
          nil ->
            "La ciudad no está registrada"

          ciudad ->
            {movs_validos, _} = Calculador.conciliar_movimientos(movimientos, ciudades)
            movs_ciudad = Enum.filter(movs_validos, &(&1.id_ciudad == ciudad.id))
            {estado, total, max_str, prom_str} = Calculador.estadisticas_ciudad(movs_ciudad)

            detalle_movs =
              if estado == :sin_movimientos do
                "  Sin movimientos registrados\n"
              else
                Enum.map_join(movs_ciudad, "\n", fn m ->
                  "  - [#{m.codigo}] #{m.hora_inicio} -> #{m.hora_final} | Magnitud: #{m.magnitud} | Profundidad: #{m.profundidad} km"
                end) <> "\n"
              end

            """
            Reporte Individual de Ciudad:
            Ciudad: #{ciudad.nombre} (ID: #{ciudad.id})
            Número de habitantes: #{ciudad.habitantes}
            Movimientos registrados:
            #{detalle_movs}  Cantidad total de movimientos: #{total}
              Movimiento de mayor magnitud: #{max_str}
              Profundidad promedio: #{prom_str}
            """
        end

      {{:error, ruta}, _} ->
        "Error: No se pudo leer el archivo #{ruta}"

      {_, {:error, ruta}} ->
        "Error: No se pudo leer el archivo #{ruta}"
    end
  end
end

ServidorSismos.start()
Process.sleep(:infinity)
