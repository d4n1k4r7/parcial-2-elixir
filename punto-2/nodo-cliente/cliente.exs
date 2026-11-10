defmodule ClienteSismos do
  def start(nodo_servidor) do
    if Process.whereis(:servicio_respuesta) do
      Process.unregister(:servicio_respuesta)
    end
    Process.register(self(), :servicio_respuesta)

    IO.puts("Intentando conectar con #{nodo_servidor}...")

    if Node.connect(nodo_servidor) do
      IO.puts("Conectado exitosamente con #{nodo_servidor}\n")
      ejecutar_solicitudes(nodo_servidor)
      recibir_respuestas_loop(1)
    else
      IO.puts(:stderr, "Error: No se pudo conectar al nodo #{nodo_servidor}")
    end
  end

  defp ejecutar_solicitudes(nodo_servidor) do
    destino_remoto = {:servicio_sismos, nodo_servidor}
    remitente = {:servicio_respuesta, node()}

    solicitudes = [
      {:reporte_ciudad, "C01"},
      {:reporte_ciudad, "C03"},
      {:reporte_ciudad, "C99"},
      :reporte_general,
      :fin
    ]

    Enum.each(solicitudes, fn sol ->
      send(destino_remoto, {remitente, sol})
    end)
  end

  defp recibir_respuestas_loop(indice) do
    receive do
      :fin ->
        IO.puts("=== Recepción finalizada (:fin recibido) ===")

      respuesta ->
        IO.puts(">>> RESPUESTA ##{indice} RECIBIDA:")
        IO.puts(respuesta)
        IO.puts("--------------------------------------------\n")
        recibir_respuestas_loop(indice + 1)
    end
  end
end

case System.argv() do
  [nodo_srv] ->
    ClienteSismos.start(String.to_atom(nodo_srv))

  _ ->
    IO.puts("Uso: elixir --sname cliente --cookie sismos_secret cliente.exs servidor@<hostname>")
end
