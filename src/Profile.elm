module Profile exposing (..)

import Api.Profile
import Components.Button
import Components.Element
import Components.Error
import Components.InputField
import Components.Misc
import Components.SvgIcon
import Data.Credentials as Credentials
import Data.OutMsg
import Data.Ports as Ports
import Data.Validation as Validation
import Dict exposing (Dict)
import File exposing (File)
import File.Select as Select
import Html exposing (Html)
import Html.Attributes as HA
import Html.Events as HE
import Http
import Json.Encode
import ResetPassword
import Task


type alias Model =
    { storeName : String
    , profilePic : Maybe String
    , email : Maybe String
    , userState : UserState
    , formState : FormState
    , editMode : Bool
    , memoName : String
    , errors : Dict String (List String)
    , resetPasswordModel : ResetPassword.Model
    }


type FormState
    = Initial
    | Loading
    | Error String
    | Success String


type UserState
    = NotVerified Credentials.Token
    | Verified Credentials.Token
    | Intruder
    | SessionExpired


type Msg
    = StoreFirstName String
    | ProfileSubmit Credentials.Token
    | ProfileDone (Result Http.Error Credentials.Token)
    | FileRequest
    | FileRequestProceed File
    | FileRead (Result Http.Error String)
    | CancelEdit
    | EditMode
    | Resend Credentials.Token
    | GotRpMsg ResetPassword.Msg


initialModel : Model
initialModel =
    { storeName = ""
    , profilePic = Nothing
    , email = Nothing
    , memoName = ""
    , formState = Initial
    , userState = Intruder
    , editMode = False
    , errors = Dict.empty
    , resetPasswordModel = ResetPassword.initialModel
    }


init : Credentials.Token -> ( Model, Cmd Msg )
init token =
    case Credentials.tokenToUserData token of
        Ok { firstname, email, isverified } ->
            ( { initialModel
                | storeName = firstname
                , email = Just email
                , userState =
                    if isverified then
                        Verified token

                    else
                        NotVerified token
              }
            , Cmd.none
            )

        Err _ ->
            ( { initialModel
                | userState = Intruder
                , email = Nothing
              }
            , Cmd.none
            )


view : Model -> Html Msg
view model =
    case model.userState of
        Verified token ->
            Html.div
                [ HA.class "flex justify-center items-start" ]
                [ Components.Element.formLayout
                    "Personal data"
                    [ if model.editMode then
                        viewEditMode model token

                      else
                        Html.div
                            []
                            [ Html.p
                                [ HA.class "mb-4 text-gray-950 dark:text-white" ]
                                [ Html.text "First Name"
                                , Html.p
                                    [ HA.class "py-2 mt-1 px-3 border dark:bg-slate-700 dark:text-white rounded text-sm border-gray-100" ]
                                    [ Html.text model.storeName ]
                                ]
                            , Components.Button.view
                                |> Components.Button.withText "Edit"
                                |> Components.Button.withMsg EditMode
                                |> Components.Button.withDisabled (model.formState == Loading)
                                |> Components.Button.withSecondaryStyle
                                |> Components.Button.toHtml
                            ]
                    ]
                , Html.div
                    []
                    [ ResetPassword.view model.resetPasswordModel |> Html.map GotRpMsg ]
                ]

        NotVerified token ->
            Html.div
                [ HA.class "flex flex-col items-center justify-center mt-64" ]
                [ Html.h2
                    [ HA.class "text-gray-950 dark:text-white" ]
                    [ Html.text "In order to access all the features please verify your email ! " ]
                , Html.p
                    [ HA.class "text-gray-950 dark:text-white" ]
                    [ Html.text "Haven't got email from us ?" ]
                , Html.div
                    [ HA.class "mt-4" ]
                    [ Components.Button.view
                        |> Components.Button.withText "Resend email"
                        |> Components.Button.withMsg (Resend token)
                        |> Components.Button.withDisabled False
                        |> Components.Button.withSecondaryStyle
                        |> Components.Button.toHtml
                    ]
                ]

        Intruder ->
            Html.div
                []
                [ Html.h2
                    []
                    [ Html.text "Hmm seems you are not logged in" ]
                , Html.p
                    []
                    [ Html.text "Please create account or login" ]
                ]

        SessionExpired ->
            Html.div
                []
                [ Html.h2
                    []
                    [ Html.text "Your session have expired" ]
                , Html.p
                    []
                    [ Html.text "Please login again" ]
                ]


viewEditMode : Model -> Credentials.Token -> Html Msg
viewEditMode model token =
    Html.div
        [ HA.class "flex flex-col gap-y-4" ]
        [ Components.InputField.view
            |> Components.InputField.withValue model.storeName
            |> Components.InputField.withMsg StoreFirstName
            |> Components.InputField.withType Components.InputField.Text
            |> Components.InputField.withDisable (model.formState == Loading)
            |> Components.InputField.withError (Components.Error.byFieldName "name" model.errors)
            |> Components.InputField.withExtraText (Components.InputField.Label "First Name")
            |> Components.InputField.toHtml
        , Html.h2
            []
            [ Html.text "Upload avatar" ]
        , Html.div
            [ HA.class "flex" ]
            [ Components.Button.view
                |> Components.Button.withText "Choose file"
                |> Components.Button.withMsg FileRequest
                |> Components.Button.withDisabled (model.formState == Loading)
                |> Components.Button.withSecondaryStyle
                |> Components.Button.withIcon Components.SvgIcon.upload
                |> Components.Button.toHtml
            ]
        , Components.Element.notification
            (Components.Element.Info "Size limit is 3mb")
        , case model.profilePic of
            Just imageString ->
                Html.div
                    [ HA.class "flex flex-col gap-3"
                    ]
                    [ Html.text "Your avatar preview"
                    , Html.img
                        [ HA.class "rounded w-[100px]"
                        , HA.src imageString
                        ]
                        []
                    ]

            Nothing ->
                Html.text ""
        , Html.div
            [ HA.class "flex gap-x-4" ]
            [ Components.Button.view
                |> Components.Button.withText "Submit"
                |> Components.Button.withMsg (ProfileSubmit token)
                |> Components.Button.withDisabled (model.formState == Loading)
                |> Components.Button.withPrimaryStyle
                |> Components.Button.toHtml
            , Components.Button.view
                |> Components.Button.withText "Cancel"
                |> Components.Button.withMsg CancelEdit
                |> Components.Button.withDisabled (model.formState == Loading)
                |> Components.Button.withSecondaryStyle
                |> Components.Button.toHtml
            ]
        , case model.formState of
            Initial ->
                Html.text ""

            Loading ->
                Components.Misc.loadingElement

            Error error ->
                Components.Element.notification (Components.Element.Error error)

            Success str ->
                Components.Element.notification
                    (Components.Element.Success str)
        ]


update : Msg -> Model -> ( Model, List Data.OutMsg.OutMsg, Cmd Msg )
update msg model =
    case msg of
        StoreFirstName firstName ->
            let
                resetErrorsPerField : Dict String (List String)
                resetErrorsPerField =
                    Validation.resetErrorsPerField "name" model.errors
            in
            ( { model
                | storeName = firstName
                , errors = resetErrorsPerField
              }
            , []
            , Cmd.none
            )

        Resend token ->
            case model.email of
                Just email ->
                    ( model
                    , [ Data.OutMsg.ResendEmail email token ]
                    , Cmd.none
                    )

                Nothing ->
                    ( model, [], Cmd.none )

        EditMode ->
            let
                resetErrorsPerField : Dict String (List String)
                resetErrorsPerField =
                    Validation.resetErrorsPerField "name" model.errors
            in
            ( { model
                | editMode = model.editMode |> not
                , memoName = model.storeName
                , errors = resetErrorsPerField
              }
            , []
            , Cmd.none
            )

        CancelEdit ->
            ( { model
                | editMode = False
                , storeName = model.memoName
              }
            , []
            , Cmd.none
            )

        ProfileSubmit token ->
            let
                imageOrNot : String
                imageOrNot =
                    -- TODO Allow user to send a form without new profile pic (but with new name only) - then BE won't proceed with changing it !
                    case model.profilePic of
                        Nothing ->
                            ""

                        Just imageUrl ->
                            imageUrl

                validationConfig : Validation.Config
                validationConfig =
                    { validationRules =
                        [ { fieldName = "name"
                          , fieldRules = [ Validation.CheckEmptyName ]
                          , fieldValue = model.storeName
                          }
                        ]
                    , initialErrors = model.errors
                    }

                potentialErrors : Dict String (List String)
                potentialErrors =
                    Validation.checkErrors validationConfig
            in
            {-
               TODO validation on Profile page is not core of the app,
               its suppose to be changed and adjusted to specific use case,
               this example (name and avatar) is just a showcase
            -}
            if Validation.anyActiveError potentialErrors then
                ( { model | errors = potentialErrors }
                , []
                , Cmd.none
                )
                -- else if model.profilePic == Nothing || model.storeName == model.memoName then
                --     ( { model | errors = Dict.insert "name" [ "State was unchanged" ] potentialErrors }
                --     , []
                --     , Cmd.none
                --     )

            else
                ( { model
                    | errors = potentialErrors
                    , formState = Loading
                  }
                , []
                , Api.Profile.submitProfile
                    token
                    { name = model.storeName, profilePic = imageOrNot }
                    ProfileDone
                )

        ProfileDone (Ok token) ->
            let
                tokenValue =
                    Credentials.encodeToken token
            in
            ( { model | formState = Success "Informations were updated" }
            , []
            , Ports.storeSession <| Just <| Json.Encode.encode 0 tokenValue
            )

        ProfileDone (Err error) ->
            ( { model | formState = Error <| Components.Error.buildErrorMessage error }
            , []
            , case error of
                Http.BadStatus statusCode ->
                    if statusCode == 401 then
                        Ports.logout

                    else
                        Cmd.none

                _ ->
                    Cmd.none
            )

        FileRequest ->
            ( model, [], Select.file [ "image/*" ] FileRequestProceed )

        FileRequestProceed file ->
            ( model, [], Task.attempt FileRead (File.toUrl file) )

        FileRead (Ok imageFileString) ->
            ( { model | profilePic = Just imageFileString }, [], Cmd.none )

        FileRead (Err error) ->
            ( { model | formState = Error <| Components.Error.buildErrorMessage error }, [], Cmd.none )

        GotRpMsg rpMsg ->
            let
                ( rpModelFromRp, rpMsgFromRp ) =
                    ResetPassword.update rpMsg model.resetPasswordModel
            in
            ( { model | resetPasswordModel = rpModelFromRp }, [], Cmd.map GotRpMsg rpMsgFromRp )
