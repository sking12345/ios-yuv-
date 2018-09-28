//
//  ViewController.m
//  vido_test
//
//  Created by sking on 25/9/18.
//  Copyright © 2018年 sking. All rights reserved.
//

#import "ViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import<AudioToolbox/AudioToolbox.h>
#include "threadpool.h"
#include <netinet/in.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <x264.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/mathematics.h>
#include <libavformat/avformat.h>
#include <libavutil/frame.h>
#include <libswscale/swscale.h>


static ViewController *instance;

@interface ViewController ()  <AVCaptureVideoDataOutputSampleBufferDelegate>
    @property(nonatomic, strong) AVCaptureSession *captureSession;
    @property (weak, nonatomic) IBOutlet UIImageView *img_view;
    @property (weak, nonatomic) IBOutlet UIImageView *img_vew1;
    @property (weak, nonatomic) IBOutlet UIButton *btn;
    @property (weak, nonatomic) IBOutlet UITextField *label_test;
@end


@implementation ViewController

int count = 0;
BOOL btn_clik = false;
threadpool_t pool,pool1;
int conect_fd = 0;

#define IMAGE_WIDTH   288
#define IMAGE_HEIGHT  352

#define CLEAR(x) (memset((&x),0,sizeof(x)))
#define ENCODER_PRESET "veryfast"    //启用各种保护质量的算法

#define ENCODER_TUNE   "zerolatency"    //不用缓存,立即返回编码数据
#define ENCODER_PROFILE  "baseline"        //avc 规格,从低到高分别为：Baseline、Main、High。
#define ENCODER_COLORSPACE X264_CSP_I420

typedef struct my_x264_encoder {
    x264_param_t  *x264_parameter;    //x264参数结构体
    x264_t  *x264_encoder;            //控制一帧一帧的编码
    x264_picture_t *yuv420p_picture; //描述视频的特征
    long colorspace;
    x264_nal_t *nal;
    int n_nal;
    char parameter_preset[20];
    char parameter_tune[20];
    char parameter_profile[20];
} my_x264_encoder;

my_x264_encoder *encoder = nil;

AVCodec *pCodec = NULL;
AVCodecContext *pCodecCtx = NULL;

AVCodecParserContext *pCodecParserCtx = NULL;
AVPacket packet = {0};
struct SwsContext *img_convert_ctx = NULL;

struct _data
{
    size_t len;
    uint8_t *data;
};


uint8_t *videoData = NULL;
int videoData_size = 0;

void* mytask1(void *arg)
{
    struct _data * data = (struct _data*)arg;
    if(data->len>0){
        if(videoData == NULL)
        {
            videoData = (uint8_t*)malloc(data->len);
        }
        videoData_size += data->len;
        videoData = (uint8_t*)realloc(videoData,videoData_size);
        int _start = videoData_size - (int)data->len;
        memcpy(videoData+_start, data->data, data->len);
    }else{
        printf("len_data:videoData_size:%d\n",videoData_size);
        AVFrame *pFrame = av_frame_alloc();
        AVPacket packet1;
        av_new_packet(&packet1, videoData_size);
        memcpy(packet1.data, videoData, videoData_size);
        int got_picture = 0;
        int ret = avcodec_decode_video2(pCodecCtx, pFrame, &got_picture, &packet1);
        if(ret>0)
        {
            if(got_picture)
            {
               int decodedBufferSize = avpicture_get_size(AV_PIX_FMT_YUV420P,IMAGE_WIDTH,IMAGE_HEIGHT);
               uint8_t * decodedBuffer = (uint8_t *)malloc(decodedBufferSize);
                avpicture_layout((AVPicture*)pFrame,AV_PIX_FMT_YUV420P,IMAGE_WIDTH,IMAGE_HEIGHT,decodedBuffer,decodedBufferSize);
                send(conect_fd,decodedBuffer,decodedBufferSize, 1);
                
            }
        }else{
             printf("len_dataavcodec_decode_video2 failed");
        }
        av_free_packet(&packet1);
        free(videoData);
        videoData_size = 0;
        videoData=NULL;
    }


    
    return NULL;
}

-(void)decodeAndShow : (uint8_t*) buf length:(int)len
{
    printf("len::::%d\n",len);
}

void* mytask(void *arg)
{
    struct _data * data = (struct _data*)arg;
    NSLog(@"len:%ld",data->len);
    printf("%s\n",encoder->parameter_preset);
    encoder->yuv420p_picture->i_pts++; //一帧的显示时间
    
    encoder->yuv420p_picture->img.plane[0] = data->data;        //y数据的首地址
    encoder->yuv420p_picture->img.plane[1] = data->data+IMAGE_WIDTH*IMAGE_HEIGHT;    //u数据的首地址
    encoder->yuv420p_picture->img.plane[2] = data->data+IMAGE_WIDTH*IMAGE_HEIGHT+IMAGE_WIDTH*IMAGE_HEIGHT/4; //v数据的首地址
    encoder->nal = (x264_nal_t *)malloc(sizeof(x264_nal_t));
    if(!encoder->nal){
        printf("malloc x264_nal_t error!\n");
        exit(EXIT_FAILURE);
    }
    CLEAR(*(encoder->nal));
    
    x264_picture_t pic_out;
    x264_nal_t *my_nal;
    
    int ret = x264_encoder_encode(encoder->x264_encoder,&encoder->nal,&encoder->n_nal,encoder->yuv420p_picture,&pic_out);
    if(ret<0)
    {
        printf("x264_encoder_encode error!\n");
        exit(EXIT_FAILURE);
    }else{
         printf("x264_encoder_encode ok!\n");
    }
    for(my_nal = encoder->nal; my_nal<encoder->nal+encoder->n_nal; ++my_nal){
        printf("h264_size:%d\n",my_nal->i_payload);
//        write(fd_write,my_nal->p_payload,my_nal->i_payload);
//        send(conect_fd, my_nal->p_payload,my_nal->i_payload,0);
        struct _data *data = (struct _data*)malloc(sizeof(struct _data));
        data->len = my_nal->i_payload;
        data->data = my_nal->p_payload;
        threadpool_add_task(&pool, mytask1, (void*)data);
    }
    struct _data *data1 = (struct _data*)malloc(sizeof(struct _data));
    data1->len = 0;
    threadpool_add_task(&pool, mytask1, (void*)data1);
    
//    send(conect_fd, data->data,data->len,0);
    free(data->data);
    data->data = NULL;
    free(data);
    data = NULL;
    return NULL;
}

void init_x264()
{
    encoder = (my_x264_encoder*)malloc(sizeof(my_x264_encoder));
    if(encoder == NULL)
    {
        printf("%s\n", "can't malloc my_x264_encoder");
        exit(EXIT_FAILURE);
    }
    CLEAR(*encoder);
    encoder->n_nal = 0;
    strcpy(encoder->parameter_preset,ENCODER_PRESET);
    strcpy(encoder->parameter_tune,ENCODER_TUNE);
    encoder->x264_parameter = (x264_param_t*)malloc(sizeof(x264_param_t));
    if(encoder->x264_parameter == NULL)
    {
        printf("malloc x264_parameter error!\n");
        exit(EXIT_FAILURE);
    }
    CLEAR(*(encoder->x264_parameter));
    x264_param_default(encoder->x264_parameter);    //自动检测系统配置默认参数
    //设置速度和质量要求
    int ret = x264_param_default_preset(encoder->x264_parameter,encoder->parameter_preset,encoder->parameter_tune);
    if( ret < 0 )
    {
        printf("%s\n", "x264_param_default_preset error");
        exit(EXIT_FAILURE);
    }
    //修改x264的配置参数
    encoder->x264_parameter->i_threads = X264_SYNC_LOOKAHEAD_AUTO;    //cpuFlags 去空缓存继续使用不死锁保证
    encoder->x264_parameter->i_width   = IMAGE_WIDTH;        //宽
    encoder->x264_parameter->i_height  = IMAGE_HEIGHT;        //高
    encoder->x264_parameter->i_frame_total = 0;    //要编码的总帧数,不知道的用0
    encoder->x264_parameter->i_keyint_max  = 25; //设定IDR帧之间的最大间隔
    encoder->x264_parameter->i_bframe        = 5;        //两个参考帧之间的B帧数目,该代码可以不设定
    encoder->x264_parameter->b_open_gop       = 0;        //GOP是指帧间的预测都是在GOP中进行的
    encoder->x264_parameter->i_bframe_pyramid  = 0; //是否允许部分B帧作为参考帧
    encoder->x264_parameter->i_bframe_adaptive = X264_B_ADAPT_TRELLIS; //自适应B帧判定
    encoder->x264_parameter->i_log_level       = X264_LOG_DEBUG;    //日志输出
    
    encoder->x264_parameter->i_fps_den         = 1;//码率分母
    encoder->x264_parameter->i_fps_num         = 25;//码率分子
    encoder->x264_parameter->b_intra_refresh   = 1;    //是否使用周期帧内涮新替换新的IDR帧
    encoder->x264_parameter->b_annexb          = 1;    //如果是ture，则nalu 之前的4个字节前缀是0x000001,
    //如果是false,则为大小
    strcpy(encoder->parameter_profile,ENCODER_PROFILE);
    ret = x264_param_apply_profile(encoder->x264_parameter,encoder->parameter_profile); //设置avc 规格
    if( ret < 0 )
    {
        printf("%s\n", "x264_param_apply_profile error");
        exit(EXIT_FAILURE);
    }
    
    encoder->x264_encoder = x264_encoder_open(encoder->x264_parameter);
    encoder->colorspace = ENCODER_COLORSPACE;    //设置颜色空间,yuv420的颜色空间
    encoder->yuv420p_picture = (x264_picture_t *)malloc(sizeof(x264_picture_t ));
    if(encoder->yuv420p_picture == NULL)
    {
        printf("%s\n", "encoder->yuv420p_picture malloc error");
        exit(EXIT_FAILURE);
    }
    //按照颜色空间分配内存,返回内存首地址
    ret = x264_picture_alloc(encoder->yuv420p_picture,encoder->colorspace,IMAGE_WIDTH,IMAGE_HEIGHT);
    if( ret<0 )
    {
        printf("%s\n", "x264_picture_alloc malloc error");
        exit(EXIT_FAILURE);
    }
    encoder->yuv420p_picture->img.i_csp = encoder->colorspace;    //配置颜色空间
    encoder->yuv420p_picture->img.i_plane = 3;                    //配置图像平面个数
    encoder->yuv420p_picture->i_type = X264_TYPE_AUTO;            //帧的类型,编码过程中自动控制
    av_init_packet(&packet);
}

void init_ffmpeg()
{
    av_register_all();
    
    pCodec = avcodec_find_decoder(AV_CODEC_ID_H264);
    pCodecCtx = avcodec_alloc_context3(pCodec);
    pCodecParserCtx = av_parser_init(AV_CODEC_ID_H264);
    if (!pCodecParserCtx){
        printf("Could not allocate video parser context\n");
        return;
    }
    if (pCodec->capabilities&CODEC_CAP_TRUNCATED)
        pCodecCtx->flags |= CODEC_FLAG_TRUNCATED;
    if (avcodec_open2(pCodecCtx, pCodec, NULL) < 0) {
        printf("Could not open codec\n");
        return ;
    }

    
}

void connect_server()
{
    const char *host = "172.20.10.7";
    int  port= 8002;
    struct sockaddr_in server_addr;
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(port);
    server_addr.sin_addr.s_addr = inet_addr(host);
    bzero(&(server_addr.sin_zero),8);
    conect_fd = socket(AF_INET, SOCK_STREAM, 0);
    if(conect_fd<0)
    {
        perror("socket error");
        return ;
    }
    if(connect(conect_fd,(struct sockaddr *)&server_addr, sizeof(struct sockaddr_in)) == -1)
    {
        perror("connect error");
    }
    return;
}

-(void) dipslay_yuv
{
    NSLog(@"xxxx");
}

- (void)viewDidLoad {
    [super viewDidLoad];
     instance = self;
    [self setcupSession];
    [self setupInput];
    [self setupOutput];
    init_x264();
    init_ffmpeg();
   
    connect_server();
    
}

-(void)change_val
{
    NSLog(@"test...");
}

//#FF00FF
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}



-(void)start{
    threadpool_init(&pool, 1);
    threadpool_init(&pool1, 1);
    
    [_captureSession startRunning];
}

-(void)stop{
    threadpool_destroy(&pool);
    threadpool_destroy(&pool1);
    [_captureSession stopRunning];
}

- (IBAction)btn_click:(id)sender {
    NSLog(@"starting....");
    if(btn_clik == false)
    {
        [self start];
        [self.btn setBackgroundColor:[UIColor greenColor]];
        [self.btn setTitle:@"停止" forState:UIControlStateNormal];
        btn_clik = true;
    }else{
        [self stop];
        btn_clik = false;
        [self.btn setBackgroundColor:[UIColor grayColor]];
        [self.btn setTitle:@"开始" forState:UIControlStateNormal];
    }
}

// 设置捕获会话： 可以设置分辨率
-(void)setcupSession{
    AVCaptureSession *captureSession = [[AVCaptureSession alloc] init];
    _captureSession = captureSession;
    captureSession.sessionPreset = AVCaptureSessionPreset352x288;
    
}

//会话添加输入对象
- (void)setupInput {
    AVCaptureDevice *videoDevice = [self deviceWithPosition:AVCaptureDevicePositionFront];
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
    if([_captureSession canAddInput:videoInput]) {
        [_captureSession addInput:videoInput];
    }
}
//会话添加输出对象
- (void)setupOutput {
    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoOutput.minFrameDuration = CMTimeMake(1,25);
    videoOutput.videoSettings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)};
    dispatch_queue_t queue = dispatch_queue_create("queue", DISPATCH_QUEUE_SERIAL);
    [videoOutput setSampleBufferDelegate:self queue:queue];
    if([_captureSession canAddOutput:videoOutput]) {
        [_captureSession addOutput:videoOutput];
    }
    AVCaptureConnection *connection = [videoOutput connectionWithMediaType:AVMediaTypeVideo];
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    connection.videoMirrored = YES;
}


- (AVCaptureDevice *)deviceWithPosition:(AVCaptureDevicePosition)position {
    NSArray *devices = [AVCaptureDevice devices];
    for (AVCaptureDevice *device in devices) {
        if(device.position == AVCaptureDevicePositionFront) {
            return device;
        }
    }
    return nil;
}


#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CIImage *ciImage = [CIImage imageWithCVImageBuffer:imageBuffer];
    UIImage *image = [UIImage imageWithCIImage:ciImage];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.img_view.image = image;
    });
    count++;
    if(count>10)
    {
        return;
    }
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    size_t pixelWidth = CVPixelBufferGetWidth(imageBuffer);
    size_t pixelHeight = CVPixelBufferGetHeight(imageBuffer);
    size_t y_size = pixelWidth * pixelHeight;
    size_t uv_size = y_size / 2;
    unsigned char *yuv_frame = (uint8_t*)malloc(uv_size + y_size);
    void *imageAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer,0); //yyyyy
    size_t row0=CVPixelBufferGetBytesPerRowOfPlane(imageBuffer,0);
    void *imageAddress1=CVPixelBufferGetBaseAddressOfPlane(imageBuffer,1);//UVUVUVUV
    size_t row1=CVPixelBufferGetBytesPerRowOfPlane(imageBuffer,1);
    for (int i=0; i<pixelHeight; ++i) {
        memcpy(yuv_frame+i*pixelWidth, imageAddress+i*row0, pixelWidth);
    }
    uint8_t *UV=imageAddress1;
    uint8_t *U=yuv_frame+y_size;
    uint8_t *V=U+y_size/4;
    for (int i=0; i<0.5*pixelHeight; i++)
    {
        for (int j=0; j<0.5*pixelWidth; j++)
        {
            *(U++)=UV[j<<1];
            *(V++)=UV[(j<<1)+1];
        }
       UV+=row1;
    }
    struct _data *p_data = (struct _data*)malloc(sizeof(struct _data));
    p_data->data = yuv_frame;
    p_data->len = uv_size + y_size;
//    p_data->encoder = encoder;
    threadpool_add_task(&pool, mytask, (void*)p_data);
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
}

@end










