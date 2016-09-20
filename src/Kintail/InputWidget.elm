module Kintail.InputWidget
    exposing
        ( InputWidget
        , State
        , Msg
        , Container
        , init
        , value
        , view
        , update
        , subscriptions
        , encodeMsg
        , decodeMsg
        , wrap
        , append
        , prepend
        , map
        , map2
        , checkbox
        , lineEdit
        , custom
        , app
        )

import Json.Encode as Encode exposing (Value)
import Json.Decode as Decode exposing (Decoder)
import Html exposing (Html)
import Html.Attributes as Html
import Html.Events as Html
import Html.App as Html
import Basics.Extra exposing (..)


type InputWidget a
    = InputWidget
        { value : a
        , html : Html Msg
        , update : Msg -> InputWidget a -> InputWidget a
        , request : Cmd Msg
        , subscriptions : Sub Msg
        }


type State msg a
    = State (Msg -> msg) (InputWidget a)


type Msg
    = Msg Value


type alias Container =
    List (Html Msg) -> Html Msg


init : (Msg -> msg) -> InputWidget a -> ( State msg a, Cmd msg )
init tag ((InputWidget impl) as inputWidget) =
    ( State tag (current inputWidget), Cmd.map tag impl.request )


value : State msg a -> a
value (State tag (InputWidget impl)) =
    impl.value


view : State msg a -> Html msg
view (State tag (InputWidget impl)) =
    Html.map tag impl.html


update : Msg -> State msg a -> ( State msg a, Cmd msg )
update message state =
    let
        (State tag inputWidget) =
            state

        (InputWidget impl) =
            inputWidget

        newInputWidget =
            impl.update message inputWidget
    in
        init tag newInputWidget


subscriptions : State msg a -> Sub msg
subscriptions (State tag (InputWidget impl)) =
    Sub.map tag impl.subscriptions


encodeMsg : Msg -> Value
encodeMsg (Msg json) =
    json


decodeMsg : Decoder Msg
decodeMsg =
    Decode.customDecoder Decode.value (\json -> Ok (Msg json))


current : InputWidget a -> InputWidget a
current (InputWidget impl) =
    InputWidget { impl | request = Cmd.none }


wrap : Container -> InputWidget a -> InputWidget a
wrap container inputWidget =
    let
        (InputWidget impl) =
            inputWidget

        value =
            impl.value

        html =
            container [ impl.html ]

        update message self =
            wrap container (impl.update message inputWidget)
    in
        InputWidget
            { value = value
            , html = html
            , update = update
            , request = impl.request
            , subscriptions = impl.subscriptions
            }


append : (a -> Html Never) -> Container -> InputWidget a -> InputWidget a
append decoration container inputWidget =
    let
        (InputWidget impl) =
            inputWidget

        value =
            impl.value

        html =
            container [ impl.html, Html.map never (decoration value) ]

        update message self =
            append decoration container (impl.update message inputWidget)
    in
        InputWidget
            { value = value
            , html = html
            , update = update
            , request = impl.request
            , subscriptions = impl.subscriptions
            }


prepend : (a -> Html Never) -> Container -> InputWidget a -> InputWidget a
prepend decoration container inputWidget =
    let
        (InputWidget impl) =
            inputWidget

        value =
            impl.value

        html =
            container [ Html.map never (decoration value), impl.html ]

        update message self =
            prepend decoration container (impl.update message inputWidget)
    in
        InputWidget
            { value = value
            , html = html
            , update = update
            , request = impl.request
            , subscriptions = impl.subscriptions
            }


map : (a -> b) -> InputWidget a -> InputWidget b
map function inputWidget =
    let
        (InputWidget impl) =
            inputWidget

        update message self =
            map function (impl.update message inputWidget)
    in
        InputWidget
            { value = function impl.value
            , html = impl.html
            , update = update
            , request = impl.request
            , subscriptions = impl.subscriptions
            }


tag : Int -> Msg -> Msg
tag index (Msg json) =
    Msg (Encode.list [ Encode.int index, json ])


decodeTagged =
    Decode.decodeValue (Decode.tuple2 (,) Decode.int Decode.value)


map2 :
    (a -> b -> c)
    -> Container
    -> InputWidget a
    -> InputWidget b
    -> InputWidget c
map2 function container inputWidgetA inputWidgetB =
    let
        (InputWidget implA) =
            inputWidgetA

        (InputWidget implB) =
            inputWidgetB

        value =
            function implA.value implB.value

        html =
            container
                [ Html.map (tag 0) implA.html
                , Html.map (tag 1) implB.html
                ]

        update (Msg json) self =
            case decodeTagged json of
                Ok ( 0, jsonA ) ->
                    let
                        updatedWidgetA =
                            implA.update (Msg jsonA) inputWidgetA
                    in
                        map2 function
                            container
                            updatedWidgetA
                            (current inputWidgetB)

                Ok ( 1, jsonB ) ->
                    let
                        updatedWidgetB =
                            implB.update (Msg jsonB) inputWidgetB
                    in
                        map2 function
                            container
                            (current inputWidgetA)
                            updatedWidgetB

                _ ->
                    current self

        request =
            Cmd.batch
                [ Cmd.map (tag 0) implA.request
                , Cmd.map (tag 1) implB.request
                ]

        subscriptions =
            Sub.batch
                [ Sub.map (tag 0) implA.subscriptions
                , Sub.map (tag 1) implB.subscriptions
                ]
    in
        InputWidget
            { value = value
            , html = html
            , update = update
            , request = request
            , subscriptions = subscriptions
            }


checkboxType =
    Html.type' "checkbox"


onCheck =
    Html.onCheck (Encode.bool >> Msg)


checkbox : List (Html.Attribute Msg) -> Bool -> InputWidget Bool
checkbox givenAttributes value =
    let
        attributes =
            checkboxType :: Html.checked value :: onCheck :: givenAttributes

        html =
            Html.input attributes []

        update (Msg json) self =
            case Decode.decodeValue Decode.bool json of
                Ok newValue ->
                    checkbox givenAttributes newValue

                Err description ->
                    current self
    in
        InputWidget
            { value = value
            , html = html
            , update = update
            , request = Cmd.none
            , subscriptions = Sub.none
            }


onInput =
    Html.onInput (Encode.string >> Msg)


lineEdit : List (Html.Attribute Msg) -> String -> InputWidget String
lineEdit givenAttributes value =
    let
        attributes =
            Html.value value :: onInput :: givenAttributes

        html =
            Html.input attributes []

        update (Msg json) self =
            case Decode.decodeValue Decode.string json of
                Ok newValue ->
                    lineEdit givenAttributes newValue

                Err description ->
                    current self
    in
        InputWidget
            { value = value
            , html = html
            , update = update
            , request = Cmd.none
            , subscriptions = Sub.none
            }


custom :
    { init : ( model, Cmd msg )
    , view : model -> Html msg
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , value : model -> a
    , encodeMsg : msg -> Value
    , decodeMsg : Decoder msg
    }
    -> InputWidget a
custom spec =
    let
        toMsg =
            spec.encodeMsg >> Msg

        ( initModel, initRequest ) =
            spec.init

        value =
            spec.value initModel

        html =
            Html.map toMsg (spec.view initModel)

        update (Msg json) self =
            case Decode.decodeValue spec.decodeMsg json of
                Ok decodedMessage ->
                    let
                        newState =
                            spec.update decodedMessage initModel
                    in
                        custom { spec | init = newState }

                Err _ ->
                    current self

        request =
            Cmd.map toMsg initRequest

        subscriptions =
            Sub.map toMsg (spec.subscriptions initModel)
    in
        InputWidget
            { value = value
            , html = html
            , update = update
            , request = request
            , subscriptions = subscriptions
            }


app : InputWidget a -> Program Never
app inputWidget =
    Html.program
        { init = init identity inputWidget
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
