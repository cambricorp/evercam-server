defmodule EvercamMedia.SnapshotController do
  use Phoenix.Controller
  use Timex
  use Calendar
  alias EvercamMedia.Util
  alias EvercamMedia.Snapshot.CamClient
  require Logger

  def show(conn, params) do
    timestamp = DateTime.now_utc |> DateTime.Format.unix
    [code, response] = [200, ConCache.get(:cache, params["id"])]
    unless response do
      [code, response] = snapshot(params["id"], params["token"])
    end
    show_respond(conn, code, response, params["id"], timestamp)
  end

  def show_last(conn, params) do
    timestamp = DateTime.now_utc |> DateTime.Format.unix
    camera_exid = params["id"]
    camera_exid_last = "#{camera_exid}_last"
    [code, response] = [200, ConCache.get(:cache, camera_exid_last)]
    unless response do
      [code, response] = snapshot(params["id"], params["token"])
    end
    show_respond(conn, code, response, params["id"], timestamp)
  end

  def show_previous(conn, params) do
    timestamp = DateTime.now_utc |> DateTime.Format.unix
    camera_exid = params["id"]
    camera_exid_previous = "#{camera_exid}_previous"
    [code, response] = [200, ConCache.get(:cache, camera_exid_previous)]
    unless response do
      [code, response] = snapshot(params["id"], params["token"])
    end
    show_respond(conn, code, response, params["id"], timestamp)
  end

  def create(conn, params) do
    [code, response] = [200, ConCache.get(:cache, params["id"])]
    unless response do
      [code, response] = snapshot(params["id"], params["token"], params["notes"])
    end
    create_respond(conn, code, response, params, params["with_data"])
  end

  def test(conn, params) do
    [code, response] = get_snapshot_response(params["username"], params["password"], params["url"], params["vendor_exid"])
    test_respond(conn, code, response, params)
  end

  defp show_respond(conn, 200, response, camera_id, timestamp) do
    Util.broadcast_snapshot(camera_id, response[:image], timestamp)

    conn
    |> put_status(200)
    |> put_resp_header("content-type", "image/jpg")
    |> put_resp_header("access-control-allow-origin", "*")
    |> text response[:image]
  end

  defp show_respond(conn, code, response, _, _) do
    conn
    |> put_status(code)
    |> put_resp_header("access-control-allow-origin", "*")
    |> json response
  end

  defp create_respond(conn, 200, response, params, "true") do
    data = "data:image/jpeg;base64,#{Base.encode64(response[:image])}"

    conn
    |> put_status(200)
    |> put_resp_header("access-control-allow-origin", "*")
    |> json %{created_at: response[:timestamp], notes: response[:notes], data: data}
  end

  defp create_respond(conn, 200, response, params, _) do
    conn
    |> put_status(200)
    |> put_resp_header("access-control-allow-origin", "*")
    |> json %{created_at: response[:timestamp], notes: response[:notes]}
  end

  defp create_respond(conn, code, response, _, _) do
    conn
    |> put_status(code)
    |> put_resp_header("access-control-allow-origin", "*")
    |> json response
  end

  defp test_respond(conn, 200, response, params) do
    data = "data:image/jpeg;base64,#{Base.encode64(response[:image])}"

    conn
    |> put_status(200)
    |> put_resp_header("access-control-allow-origin", "*")
    |> json %{data: data, status: "ok"}
  end

  defp test_respond(conn, code, response, _) do
    conn
    |> put_status(code)
    |> put_resp_header("access-control-allow-origin", "*")
    |> json response
  end

  defp snapshot(camera_id, token, notes \\ "Evercam Proxy") do
    vendor_exid = Camera.get_vendor_exid_by_camera_exid(camera_id)
    get_snapshot_response(token, vendor_exid)
  end

  defp get_snapshot_response(username, password, url, vendor_exid) do
    args = %{
      vendor_exid: vendor_exid,
      url: url,
      username: username,
      password: password
    }
    get_snapshot(args)
  end

  defp get_snapshot_response(token, vendor_exid) do
    [url, auth, credentials, time, _] = Util.decode_request_token(token)
    args = %{
      vendor_exid: vendor_exid,
      url: url,
      auth: auth
    }
    get_snapshot(args)
  end

  defp get_snapshot(args) do
    case res = CamClient.fetch_snapshot(args) do
      {:ok, data} ->
        response =  %{image: data}
        [200, response]
      {:error, "Response not a jpeg image"} ->
        [504, %{message: "Camera didn't respond with an image."}]
      {:error, %HTTPoison.Response{}} ->
        [504, %{message: res.body}]
      {:error, %HTTPoison.Error{}} ->
        [504, %{message: "Camera seems to be offline."}]
       _ ->
         [500, %{message: "Sorry, we dropped the ball."}]
    end
  end

  defp check_token_expiry(time) do
    token_time = DateFormat.parse! time, "{ISOz}"
    token_time = Date.shift token_time, mins: 5

    if Date.now > token_time do
      raise FunctionClauseError
    end
  end
end
